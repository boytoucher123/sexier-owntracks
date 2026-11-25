"""Tests for flock-server, against temporary files and a real HTTP server.

    python3 server/test_flock_server.py
"""
import base64
import importlib.machinery
import importlib.util
import json
import os
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
TMP = tempfile.mkdtemp(prefix="flock-test-")
os.environ.update(
    FLOCK_PASSWD=os.path.join(TMP, "passwd"),
    FLOCK_ACL=os.path.join(TMP, "acl"),
    FLOCK_DB=os.path.join(TMP, "flock.db"),
    FLOCK_RELOAD="0",
)
_loader = importlib.machinery.SourceFileLoader("flock_server", os.path.join(HERE, "flock-server"))
_spec = importlib.util.spec_from_loader("flock_server", _loader)
fs = importlib.util.module_from_spec(_spec)
_loader.exec_module(fs)
fs.time.sleep = lambda s: None   # no delay on wrong passwords in tests


class Api:
    def __init__(self, port):
        self.base = f"http://127.0.0.1:{port}"

    def call(self, method, path, body=None, login=None, headers=None, ip="10.0.0.1"):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(self.base + path, data=data, method=method)
        req.add_header("X-Forwarded-For", ip)
        if data is not None:
            req.add_header("Content-Type", "application/json")
        if login:
            tok = base64.b64encode(f"{login['username']}:{login['password']}".encode()).decode()
            req.add_header("Authorization", "Basic " + tok)
        for k, v in (headers or {}).items():
            req.add_header(k, v)
        try:
            with urllib.request.urlopen(req) as r:
                raw = r.read()
                return r.status, (json.loads(raw) if raw else None)
        except urllib.error.HTTPError as e:
            raw = e.read()
            e.close()
            return e.code, (json.loads(raw) if raw else None)


class FlockServerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # The Recorder's own account already exists, as on the real server.
        with open(fs.PASSWD, "w") as f:
            f.write("recorder:" + fs.hash_password("recorder-secret") + "\n")
        cls.httpd = ThreadingHTTPServer(("127.0.0.1", 0), fs.Handler)
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()
        cls.api = Api(cls.httpd.server_address[1])

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()

    def setUp(self):
        fs._signups.clear()
        fs._signups_ip.clear()
        fs._joins.clear()
        fs._fails.clear()
        fs._blocked.clear()

    def signup(self, name, ip=None):
        ip = ip or f"10.1.{len(fs._signups_ip)}.1"
        status, body = self.api.call("POST", "/flock/api/signup", {"name": name}, ip=ip)
        self.assertEqual(status, 201, body)
        return body

    # ---------------------------------------------------------------------

    def test_usernames_come_from_the_name(self):
        self.assertEqual(fs.username_base("Maya Chen"), "maya-chen")
        self.assertEqual(fs.username_base("Zoë O'Brien"), "zoe-obrien")
        self.assertEqual(fs.username_base("  Jack   LEE  "), "jack-lee")
        self.assertEqual(fs.username_base("李雷"), "friend")
        self.assertEqual(len(fs.username_base("A" * 80)), 20)

    def test_signup_makes_a_working_mosquitto_login(self):
        a = self.signup("Signup Person")
        self.assertEqual(a["username"], "signup-person")
        self.assertGreaterEqual(len(a["password"]), 24)
        stored = fs._read_passwd()[a["username"]]
        self.assertTrue(stored.startswith("$7$101$"))
        self.assertTrue(fs.check_hash(a["password"], stored))
        self.assertIn("recorder", fs._read_passwd())  # untouched
        status, me = self.api.call("GET", "/flock/api/me", login=a)
        self.assertEqual(status, 200)
        self.assertEqual(me["name"], "Signup Person")
        self.assertEqual(me["groups"], [])

    def test_same_name_gets_a_number_and_reserved_names_are_skipped(self):
        a = self.signup("Twin Name")
        b = self.signup("Twin Name")
        self.assertEqual((a["username"], b["username"]), ("twin-name", "twin-name-2"))
        r = self.signup("Recorder")
        self.assertEqual(r["username"], "recorder-2")
        f = self.signup("Flock Test")
        self.assertEqual(f["username"], "flock-test")

    def test_bad_names_and_logins(self):
        s, b = self.api.call("POST", "/flock/api/signup", {"name": "   "})
        self.assertEqual(s, 400)
        self.assertIn("name", b["error"])
        s, _ = self.api.call("GET", "/flock/api/me")
        self.assertEqual(s, 401)
        s, _ = self.api.call("GET", "/flock/api/me", login={"username": "recorder", "password": "recorder-secret"})
        self.assertEqual(s, 401)   # the Recorder's login is not a person
        a = self.signup("Wrong Pass")
        s, _ = self.api.call("GET", "/flock/api/me", login={**a, "password": "nope"})
        self.assertEqual(s, 401)

    def test_signup_rate_limit_per_ip(self):
        for i in range(fs.SIGNUPS_PER_IP_HOUR):
            self.signup(f"Rate {i}", ip="10.9.9.9")
        s, b = self.api.call("POST", "/flock/api/signup", {"name": "Rate X"}, ip="10.9.9.9")
        self.assertEqual(s, 429)

    def test_wrong_passwords_block_the_ip(self):
        a = self.signup("Blocked Person")
        bad = {**a, "password": "x"}
        for _ in range(fs.MAX_FAILS):
            self.api.call("GET", "/flock/api/me", login=bad, ip="10.7.7.7")
        s, _ = self.api.call("GET", "/flock/api/me", login=a, ip="10.7.7.7")
        self.assertEqual(s, 429)
        s, _ = self.api.call("GET", "/flock/api/me", login=a, ip="10.7.7.8")
        self.assertEqual(s, 200)

    def test_group_join_approve_and_what_the_acl_allows(self):
        leader = self.signup("Group Leader")
        joiner = self.signup("Group Joiner")
        s, me = self.api.call("POST", "/flock/api/groups", {"name": "Class of 2024"}, login=leader)
        self.assertEqual(s, 201)
        g = me["groups"][0]
        self.assertEqual((g["role"], g["name"]), ("leader", "Class of 2024"))
        self.assertRegex(g["code"], r"^[A-Z2-9]{3}-[A-Z2-9]{3}$")

        # Joining with a lower-case code without the dash still works.
        s, jme = self.api.call("POST", "/flock/api/join", {"code": g["code"].lower().replace("-", "")}, login=joiner)
        self.assertEqual(s, 200, jme)
        self.assertEqual(jme["pending"][0]["leader_name"], "Group Leader")
        self.assertEqual(jme["visible"], [])

        acl = open(fs.ACL).read()
        joiner_block = acl.split(f"user {joiner['username']}\n")[1].split("\n\n")[0]
        self.assertNotIn(f"owntracks/{leader['username']}", joiner_block)
        leader_block = acl.split(f"user {leader['username']}\n")[1].split("\n\n")[0]
        # The leader can see the requester's card (name and photo) only.
        self.assertIn(f"topic read owntracks/{joiner['username']}/phone/info", leader_block)
        self.assertNotIn(f"topic read owntracks/{joiner['username']}/#", leader_block)

        _, lme = self.api.call("GET", "/flock/api/me", login=leader)
        self.assertEqual([r["username"] for r in lme["groups"][0]["requests"]], [joiner["username"]])

        # Only the leader can approve.
        s, _ = self.api.call("POST", f"/flock/api/groups/{g['id']}/requests/{joiner['username']}/approve", login=joiner)
        self.assertEqual(s, 403)
        s, lme = self.api.call("POST", f"/flock/api/groups/{g['id']}/requests/{joiner['username']}/approve", login=leader)
        self.assertEqual(s, 200)
        self.assertEqual([v["username"] for v in lme["visible"]], [joiner["username"]])

        acl = open(fs.ACL).read()
        joiner_block = acl.split(f"user {joiner['username']}\n")[1].split("\n\n")[0]
        self.assertIn(f"topic read owntracks/{leader['username']}/#", joiner_block)
        self.assertIn(f"topic write owntracks/{leader['username']}/phone/cmd", joiner_block)
        self.assertIn(f"topic readwrite owntracks/{joiner['username']}/#", joiner_block)
        self.assertTrue(acl.startswith("#") and "user recorder\ntopic read owntracks/#" in acl)

        # History: own and group only, locations only.
        def check(login, user, path="/api/0/locations", method="GET"):
            s, _ = self.api.call("GET", "/check", login=login, headers={
                "X-Forwarded-Uri": f"{path}?user={user}&device=phone&format=json",
                "X-Forwarded-Method": method,
            })
            return s
        stranger = self.signup("Total Stranger")
        self.assertEqual(check(joiner, leader["username"]), 200)
        self.assertEqual(check(joiner, joiner["username"]), 200)
        self.assertEqual(check(stranger, leader["username"]), 403)
        self.assertEqual(check(joiner, leader["username"], path="/api/0/last"), 403)
        self.assertEqual(check(joiner, leader["username"], method="POST"), 403)
        s, _ = self.api.call("GET", "/check", headers={"X-Forwarded-Uri": "/api/0/locations?user=x"})
        self.assertEqual(s, 401)

        # Leader leaves: the other member takes over.
        s, lme = self.api.call("DELETE", f"/flock/api/groups/{g['id']}/members/{leader['username']}", login=leader)
        self.assertEqual(s, 200)
        self.assertEqual(lme["groups"], [])
        _, jme = self.api.call("GET", "/flock/api/me", login=joiner)
        self.assertEqual(jme["groups"][0]["role"], "leader")
        self.assertEqual(check(joiner, leader["username"]), 403)

    def test_deny_new_code_rename_and_delete_account(self):
        leader = self.signup("Deny Leader")
        asker = self.signup("Deny Asker")
        _, me = self.api.call("POST", "/flock/api/groups", {"name": "Crew"}, login=leader)
        g = me["groups"][0]
        self.api.call("POST", "/flock/api/join", {"code": g["code"]}, login=asker)
        s, me = self.api.call("POST", f"/flock/api/groups/{g['id']}/requests/{asker['username']}/deny", login=leader)
        self.assertEqual((s, me["groups"][0]["requests"]), (200, []))
        _, ame = self.api.call("GET", "/flock/api/me", login=asker)
        self.assertEqual(ame["pending"], [])

        s, me = self.api.call("POST", f"/flock/api/groups/{g['id']}/code", login=leader)
        self.assertNotEqual(me["groups"][0]["code"], g["code"])
        s, b = self.api.call("POST", "/flock/api/join", {"code": g["code"]}, login=asker)
        self.assertEqual(s, 404)

        s, me = self.api.call("PATCH", f"/flock/api/groups/{g['id']}", {"name": "The Crew"}, login=leader)
        self.assertEqual(me["groups"][0]["name"], "The Crew")
        s, me = self.api.call("PATCH", "/flock/api/me", {"name": "Deny Boss"}, login=leader)
        self.assertEqual((me["name"], me["username"]), ("Deny Boss", "deny-leader"))

        s, _ = self.api.call("DELETE", "/flock/api/me", login=leader)
        self.assertEqual(s, 204)
        self.assertNotIn(leader["username"], fs._read_passwd())
        self.assertNotIn(f"user {leader['username']}\n", open(fs.ACL).read())
        s, _ = self.api.call("GET", "/flock/api/me", login=leader)
        self.assertEqual(s, 401)

    def test_join_attempts_are_limited(self):
        a = self.signup("Code Guesser")
        for _ in range(fs.JOINS_PER_USER_HOUR):
            self.api.call("POST", "/flock/api/join", {"code": "AAA-AAA"}, login=a)
        s, _ = self.api.call("POST", "/flock/api/join", {"code": "AAA-AAA"}, login=a)
        self.assertEqual(s, 429)


if __name__ == "__main__":
    unittest.main(verbosity=1)
