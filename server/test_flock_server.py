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
    FLOCK_SERVER_CONF=os.path.join(TMP, "server.json"),
)
TEST_CA = """-----BEGIN CERTIFICATE-----
MIIBszCCAVmgAwIBAgIUQ2xUb2NrVGVzdENBMDAwMDAwMDAwMDAwCgYIKoZIzj0EAwIw
-----END CERTIFICATE-----
"""
with open(os.path.join(TMP, "ca.crt"), "w") as _f:
    _f.write(TEST_CA)
with open(os.environ["FLOCK_SERVER_CONF"], "w") as _f:
    json.dump({"public_host": "flock.example.net", "api_port": 8443,
               "mqtt_port": 8883, "ca_file": os.path.join(TMP, "ca.crt")}, _f)
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


_api = None


def server():
    """One flock-server for all tests, on temporary files."""
    global _api
    if _api is None:
        # The Recorder's own account already exists, as on the real server.
        with open(fs.PASSWD, "w") as f:
            f.write("recorder:" + fs.hash_password("recorder-secret") + "\n")
        httpd = ThreadingHTTPServer(("127.0.0.1", 0), fs.Handler)
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        _api = Api(httpd.server_address[1])
    return _api


class FlockServerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.api = server()

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
        fs.set_standard(g["id"])   # a group that runs on this server
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



class GroupConfigTest(unittest.TestCase):
    """Group settings: new groups bring their own server; only standard
    groups get to use this one."""

    api = None

    @classmethod
    def setUpClass(cls):
        cls.api = server()

    def setUp(self):
        fs._signups.clear()
        fs._signups_ip.clear()
        fs._joins.clear()

    def signup(self, name):
        s, b = self.api.call("POST", "/flock/api/signup", {"name": name}, ip=f"10.3.{len(fs._signups)}.1")
        self.assertEqual(s, 201, b)
        return b

    def group(self, leader, name):
        _, me = self.api.call("POST", "/flock/api/groups", {"name": name}, login=leader)
        return [g for g in me["groups"] if g["name"] == name][0]

    def test_new_groups_get_nothing_on_this_server(self):
        leader = self.signup("Random Leader")
        friend = self.signup("Random Friend")
        g = self.group(leader, "Randoms")
        self.assertIsNone(g["config"])
        self.api.call("POST", "/flock/api/join", {"code": g["code"]}, login=friend)
        self.api.call("POST", f"/flock/api/groups/{g['id']}/requests/{friend['username']}/approve", login=leader)
        acl = open(fs.ACL).read()
        self.assertNotIn(f"user {leader['username']}\n", acl)
        self.assertNotIn(f"user {friend['username']}\n", acl)
        s, _ = self.api.call("GET", "/check", login=leader, headers={
            "X-Forwarded-Uri": f"/api/0/locations?user={leader['username']}", "X-Forwarded-Method": "GET"})
        self.assertEqual(s, 403)
        s, _ = self.api.call("GET", "/check", login=friend, headers={
            "X-Forwarded-Uri": f"/api/0/locations?user={leader['username']}", "X-Forwarded-Method": "GET"})
        self.assertEqual(s, 403)

    def test_leader_sets_their_own_server_and_members_get_it(self):
        leader = self.signup("Own Server Leader")
        friend = self.signup("Own Server Friend")
        asker = self.signup("Own Server Asker")
        g = self.group(leader, "Own Server")
        cfg = {"host": "mqtt.example.com", "port": 8883, "tls": True,
               "username": "crew", "password": "s3cret",
               "recorder_url": "https://mqtt.example.com/owntracks",
               "tracking_mode": "precise"}
        s, b = self.api.call("PUT", f"/flock/api/groups/{g['id']}/config", cfg, login=friend)
        self.assertEqual(s, 403)  # not the leader
        s, me = self.api.call("PUT", f"/flock/api/groups/{g['id']}/config", cfg, login=leader)
        self.assertEqual(s, 200, me)
        got = [x for x in me["groups"] if x["id"] == g["id"]][0]["config"]
        self.assertEqual((got["standard"], got["host"], got["password"], got["tracking_mode"]),
                         (False, "mqtt.example.com", "s3cret", "precise"))
        self.assertEqual(got["topic_prefix"], "owntracks")

        self.api.call("POST", "/flock/api/join", {"code": g["code"]}, login=friend)
        self.api.call("POST", "/flock/api/join", {"code": g["code"]}, login=asker)
        self.api.call("POST", f"/flock/api/groups/{g['id']}/requests/{friend['username']}/approve", login=leader)
        _, fme = self.api.call("GET", "/flock/api/me", login=friend)
        self.assertEqual(fme["groups"][0]["config"]["username"], "crew")
        _, ame = self.api.call("GET", "/flock/api/me", login=asker)
        self.assertNotIn("config", json.dumps(ame["pending"]))  # not until let in
        self.assertNotIn("s3cret", json.dumps(ame))

        # Tracking mode alone keeps the server.
        s, me = self.api.call("PUT", f"/flock/api/groups/{g['id']}/config", {"tracking_mode": "batterySaver"}, login=leader)
        got = [x for x in me["groups"] if x["id"] == g["id"]][0]["config"]
        self.assertEqual((got["host"], got["tracking_mode"]), ("mqtt.example.com", "batterySaver"))

    def test_bad_settings_are_refused_in_plain_english(self):
        leader = self.signup("Bad Config Leader")
        g = self.group(leader, "Bad Config")
        def put(body):
            return self.api.call("PUT", f"/flock/api/groups/{g['id']}/config", body, login=leader)
        s, b = put({"tracking_mode": "precise"})
        self.assertEqual((s, b["error"]), (400, "Add your server's details first."))
        s, b = put({"host": "https://x.com/", "username": "u"})
        self.assertEqual(s, 400)
        self.assertIn("server name", b["error"])
        s, b = put({"host": "x.com", "username": "u", "port": 70000})
        self.assertEqual(s, 400)
        s, b = put({"host": "x.com", "username": "u", "ca": "not a cert"})
        self.assertIn("PEM", b["error"])
        s, b = put({"host": "x.com"})
        self.assertIn("username", b["error"])

    def test_standard_group_can_change_tracking_but_leaving_is_for_good(self):
        leader = self.signup("Std Leader")
        g = self.group(leader, "Std")
        fs.set_standard(g["id"])
        self.assertIn(f"user {leader['username']}\n", open(fs.ACL).read())
        s, me = self.api.call("PUT", f"/flock/api/groups/{g['id']}/config", {"tracking_mode": "precise"}, login=leader)
        got = [x for x in me["groups"] if x["id"] == g["id"]][0]["config"]
        self.assertEqual((got["standard"], got["tracking_mode"]), (True, "precise"))
        stored = json.loads(fs.db().execute("SELECT config FROM groups WHERE id=?", (g["id"],)).fetchone()[0])
        self.assertEqual(stored, {"standard": True, "tracking_mode": "precise"})  # no address frozen in
        self.api.call("PUT", f"/flock/api/groups/{g['id']}/config",
                      {"host": "elsewhere.example", "username": "u"}, login=leader)
        self.assertNotIn(f"user {leader['username']}\n", open(fs.ACL).read())


class InviteTest(unittest.TestCase):
    """The app knows no server: invites and standard groups tell it."""

    @classmethod
    def setUpClass(cls):
        cls.api = server()

    def test_ca_is_served_and_invites_pin_it(self):
        s, b = self.api.call("GET", "/flock/api/ca")
        self.assertEqual((s, b["pem"]), (200, TEST_CA))
        fs._signups_ip.clear()
        _, leader = self.api.call("POST", "/flock/api/signup", {"name": "Invite Leader"}, ip="10.8.0.1")
        _, me = self.api.call("POST", "/flock/api/groups", {"name": "Inv"}, login=leader)
        g = me["groups"][0]
        fp = fs.ca_fingerprint(TEST_CA)
        self.assertEqual(g["invite"], f"https://flock.example.net:8443/flock/join/{g['code']}?ca={fp}")
        self.assertEqual(len(fp), 43)

        # The link's page opens Flock with the same invite.
        import urllib.request
        with urllib.request.urlopen(f"{self.api.base}/flock/join/{g['code']}") as r:
            page = r.read().decode()
            self.assertEqual(r.headers["Content-Type"], "text/html; charset=utf-8")
        self.assertIn(f'href="flock://flock.example.net:8443/join/{g["code"]}?ca={fp}"', page)
        self.assertIn(g["code"], page)

    def test_standard_groups_carry_this_servers_details(self):
        fs._signups_ip.clear()
        _, leader = self.api.call("POST", "/flock/api/signup", {"name": "Std Details"}, ip="10.8.0.2")
        _, me = self.api.call("POST", "/flock/api/groups", {"name": "StdD"}, login=leader)
        fs.set_standard(me["groups"][0]["id"])
        _, me = self.api.call("GET", "/flock/api/me", login=leader)
        c = me["groups"][0]["config"]
        self.assertEqual(
            (c["standard"], c["host"], c["port"], c["ca"], c["recorder_url"], c["topic_prefix"]),
            (True, "flock.example.net", 8883, TEST_CA, "https://flock.example.net:8443", "owntracks"),
        )


class MigrationTest(unittest.TestCase):
    def test_groups_from_before_settings_become_standard(self):
        import sqlite3
        path = os.path.join(TMP, "old.db")
        c = sqlite3.connect(path)
        c.executescript("""
            CREATE TABLE users (username TEXT PRIMARY KEY, name TEXT NOT NULL, created INTEGER NOT NULL);
            CREATE TABLE groups (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
              leader TEXT NOT NULL, code TEXT NOT NULL UNIQUE, created INTEGER NOT NULL);
            INSERT INTO users VALUES ('george', 'George', 1);
            INSERT INTO groups (name, leader, code, created) VALUES ('Class of 2024', 'george', 'ABCDEF', 1);
        """)
        c.commit()
        c.close()
        saved_db, saved_conn = fs.DB, fs._conn
        try:
            fs.DB, fs._conn = path, None
            row = fs.db().execute("SELECT config FROM groups").fetchone()
            self.assertEqual(json.loads(row[0]), {"standard": True, "tracking_mode": "balanced"})
            c2 = fs.db()
            c2.execute("INSERT INTO groups (name, leader, code, created) VALUES ('New', 'george', 'GHJKLM', 2)")
            c2.commit()
            c2.close()
            fs._conn = None   # reopening must not upgrade newer groups
            new = fs.db().execute("SELECT config FROM groups WHERE name='New'").fetchone()
            self.assertIsNone(new[0])
        finally:
            fs._conn.close()
            fs.DB, fs._conn = saved_db, saved_conn


if __name__ == "__main__":
    unittest.main(verbosity=1)
