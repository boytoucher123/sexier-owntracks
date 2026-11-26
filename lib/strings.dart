/// Every piece of text the app shows, in one place. Change wording here;
/// the screens only refer to these names. Text with a name or number in it
/// is a small function: keep the `${...}` parts, reword around them.
// ignore_for_file: unnecessary_brace_in_string_interps
library;

abstract final class Txt {
  // ---- App -------------------------------------------------------------------

  static const flock = 'Flock';

  // ---- Tracking modes --------------------------------------------------------

  static const saver = 'Saver';
  static const balanced = 'Balanced';
  static const precise = 'Precise';
  static const updatesWhenYouMoveAbout =
      'Updates when you move about 500 m. Easiest on battery.';
  static const updatesEvery100MOf =
      'Updates every ~100 m of movement. Recommended.';
  static const frequentExactUpdatesUsesNoticeably =
      'Frequent, exact updates. Uses noticeably more battery.';

  // ---- Group settings (leaders) ----------------------------------------------

  static const moveToYourOwnServer = 'Move to your own server?';
  static const everyoneInTheGroupSwitches =
      'Everyone in the group switches to your server. You can\'t move '
      'back afterwards.';
  static const cancel = 'Cancel';
  static const move = 'Move';
  static const savedEveryoneInTheGroup =
      'Saved. Everyone in the group gets it automatically.';
  static String settings(Object? name) => '${name} settings';
  static String everyoneInGetsTheseSettings(Object? name) =>
      'Everyone in ${name} gets these settings automatically. They '
      'don\'t have to set anything up.';
  static const tracking = 'Tracking';
  static const setUpTheServerFirst = 'Set up the server first.';
  static const server = 'Server';
  static const runsOnThisAppS =
      'Runs on the server your accounts are on. Everyone uses their own '
      'login, and history is included. Nothing to set up.';
  static const useYourOwnServerInstead = 'Use your own server instead';
  static const newGroupsBringTheirOwn =
      'New groups bring their own server: an MQTT broker '
      '(like Mosquitto) that everyone\'s phone can reach. The '
      'whole group shares the one login below; the app keeps '
      'people apart by name. Until you add it, nobody in the '
      'group can share their location.';
  static const serverAddress = 'Server address';
  static const eGMqttExampleCom = 'e.g. mqtt.example.com';
  static const port = 'Port';
  static const secureTls = 'Secure (TLS)';
  static const groupLoginUsername = 'Group login: username';
  static const groupLoginPassword = 'Group login: password';
  static const historyAddressOptional = 'History address (optional)';
  static const moreOptions = 'More options';
  static const topicPrefix = 'Topic prefix';
  static const serverCertificateCaOptional =
      'Server certificate (CA, optional)';
  static const pasteThePemIfYour =
      'Paste the PEM if your server uses its own certificate '
      'authority';
  static const testing = 'Testing…';
  static const testConnection = 'Test connection';
  static const saving = 'Saving…';
  static const save = 'Save';

  // ---- Groups ----------------------------------------------------------------

  static const groups = 'Groups';
  static const youReNotInA =
      'You\'re not in a group yet. Start one and share its '
      'code, or ask someone for theirs.';
  static const joinAGroup = 'Join a group';
  static const startAGroup = 'Start a group';
  static const leader = 'Leader';
  static const groupOptions = 'Group options';
  static const renameGroup = 'Rename group';
  static const leaveGroup = 'Leave group';
  static const n1PersonWantsToJoin = '1 person wants to join';
  static String peopleWantToJoin(Object? requestsCount) =>
      '${requestsCount} people want to join';
  static const groupName = 'Group name';
  static String leave(Object? name) => 'Leave ${name}?';
  static const youLlStopSeeingEveryone =
      'You\'ll stop seeing everyone in it, and they\'ll stop seeing '
      'you. The longest-standing member becomes the leader.';
  static const youReTheOnlyOne =
      'You\'re the only one in it, so the group will be deleted.';
  static const youLlStopSeeingEveryone2 =
      'You\'ll stop seeing everyone in it, and they\'ll stop seeing you.';
  static const leave2 = 'Leave';
  static const notSetUpYetAdd =
      'Not set up yet. Add a server so the group can share '
      'locations.';
  static String waitingForToSetUp(Object? leaderName) =>
      'Waiting for ${leaderName} to set up a server for the '
      'group.';
  static const setUp = 'Set up';
  static String tracking2(Object? trackingMode) => 'Tracking: ${trackingMode}';
  static String server2(Object? server) => 'Server: ${server}';
  static const settings2 = 'Settings';
  static const onYourMapNow = 'On your map now';
  static const showThisGroupOnMy = 'Show this group on my map';
  static String waitingForToLetYou(Object? leaderName) =>
      'Waiting for ${leaderName} to let you in. '
      'Let them know it\'s you.';
  static String joinOnFlockInstallFlock(Object? name, Object? code) =>
      'Join "${name}" on Flock. Install Flock, then paste this whole '
      'message when it asks for an invite:\n\n${code}';
  static const inviteCode = 'Invite code';
  static const copy = 'Copy';
  static const inviteCopied = 'Invite copied.';
  static const newCode = 'New code';
  static const makeANewCode = 'Make a new code?';
  static const theOldCodeStopsWorking =
      'The old code stops working. People already in the '
      'group stay in.';
  static const joinMeOnFlock = 'Join me on Flock';
  static const shareInvite = 'Share invite';
  static const shareSendsTheFullInvite =
      'Share sends the full invite (this code plus where your server '
      'is). Anyone with it can ask to join; you decide who gets in.';
  static String newToFlock(Object? username, Object? accountCreated) =>
      '@${username} · new to Flock ${accountCreated}';
  static const sayNo = 'Say no';
  static const letIn = 'Let in';
  static String nameYou(Object? name) => '${name} (you)';
  static String optionsFor(Object? name) => 'Options for ${name}';
  static String remove(Object? name) => 'Remove ${name}?';
  static String theyLlStopSeeingEveryone(Object? name) =>
      'They\'ll stop seeing everyone in ${name}, and '
      'everyone stops seeing them.';
  static const remove2 = 'Remove';
  static String makeTheLeader(Object? name) => 'Make ${name} the leader?';
  static const theyLlApproveNewPeople =
      'They\'ll approve new people and manage the code. '
      'You stay in the group.';
  static const makeLeader = 'Make leader';
  static const removeFromGroup = 'Remove from group';
  static const eGTheCrew = 'e.g. The Crew';
  static const start = 'Start';
  static const invite = 'Invite';
  static const pasteTheInviteYouWere = 'Paste the invite you were sent';
  static const paste = 'Paste';
  static const askToJoin = 'Ask to join';

  // ---- History ---------------------------------------------------------------

  static const dailyHistory = 'Daily history';
  static const noLocationsRecordedOnThis = 'No locations recorded on this day.';
  static const earlierDay = 'Earlier day';
  static const laterDay = 'Later day';
  static String kmH(Object? velocityKmh) => '${velocityKmh} km/h';
  static const findingAddress = 'Finding address…';

  // ---- Home ------------------------------------------------------------------

  static const showEveryone = 'Show everyone';
  static const me = 'Me';
  static const live = 'Live';
  static const connecting = 'Connecting…';
  static const offline = 'Offline';
  static const canTConnect = 'Can\'t connect';
  static const people = 'People';
  static const youReNotSharingYour =
      'You\'re not sharing your location. Turn it on in Settings.';
  static String addAServerForSo(Object? name) =>
      'Add a server for ${name} so everyone can share their '
      'location.';
  static String isnTSetUpYet(Object? name, Object? leaderName) =>
      '${name} isn\'t set up yet. ${leaderName} needs to add '
      'a server.';
  static String wantsToJoin(Object? name, Object? name2) =>
      '${name} wants to join ${name2}.';
  static String peopleWantToJoin2(Object? requestsCount, Object? name) =>
      '${requestsCount} people want to join ${name}.';
  static String waitingForToLetYou2(Object? leaderName, Object? name) =>
      'Waiting for ${leaderName} to let you into ${name}.';
  static const noOneElseHereYet =
      'No one else here yet. Share your group\'s code from '
      'Groups so your friends can ask to join.';
  static const youReNotInA2 =
      'You\'re not in a group yet. Start one, or enter a '
      'code someone sent you, in Groups.';
  static const noLocationYet = 'No location yet';
  static const backToEveryone = 'Back to everyone';
  static const update = 'Update';
  static const refresh = 'Refresh';
  static const sendingYourLocation = 'Sending your location…';
  static String askedSPhoneForAn(Object? name) =>
      'Asked ${name}\'s phone for an update.';
  static const youReOfflineRightNow = 'You\'re offline right now.';
  static const directions = 'Directions';
  static const history = 'History';

  // ---- Setup (onboarding) ----------------------------------------------------

  static const stayCloseToYourPeople = 'Stay close to\nyour people';
  static const seeWhereYourFriendsAre =
      'See where your friends are, check they got home safe, and look back '
      'at their day. On your own server, so it stays private.';
  static const getStarted = 'Get started';
  static const whoAreYou = 'Who are you?';
  static const thisIsHowYouLl =
      'This is how you\'ll appear to everyone else. Use your real name '
      'so your group leader knows it\'s you.';
  static const continueButton = 'Continue';
  static const addAPhoto = 'Add a photo';
  static const changePhoto = 'Change photo';
  static const yourName = 'Your name';
  static const eGFredDurk = 'e.g. Fred Durk';
  static const initials = 'Initials';
  static const shownOnTheMapWhen = 'Shown on the map when there\'s no photo';
  static const takeAPhoto = 'Take a photo';
  static const chooseFromLibrary = 'Choose from library';
  static const removePhoto = 'Remove photo';
  static const joinYourGroup = 'Join your group';
  static const pasteTheInviteYourGroup =
      'Paste the invite your group leader sent you.';
  static const noInviteAskThePerson =
      'No invite? Ask the person who runs your group to open Flock, go '
      'to Groups and tap Share invite.';
  static const shareYourLocation = 'Share your location';
  static const yourFriendsSeeYouOn =
      'Your friends see you on the map only when you allow location access.';
  static const allowLocation = 'Allow location';
  static const oneMoreThing = 'One more thing';
  static const chooseAllowAllTheTime =
      'Choose "Allow all the time" so your friends can still see you when the '
      'app is closed. Without it, your dot only moves while the app is open.';
  static const allowAllTheTime = 'Allow all the time';
  static const youReAllSet = 'You\'re all set';
  static const yourLocationWillBeShared =
      'Your location will be shared in the background. You can pause sharing '
      'any time from Settings.';
  static const locationIsBlocked = 'Location is blocked';
  static const locationAccessWasTurnedOff =
      'Location access was turned off for this app. Open Settings and allow '
      'location "All the time".';
  static const openSettings = 'Open Settings';
  static const locationIsOff = 'Location is off';
  static const locationServicesAreTurnedOff =
      'Location services are turned off on this phone.';
  static const turnOnLocation = 'Turn on location';
  static const notNow = 'Not now';
  static const allowLocationWhileUsingThe =
      'Allow location while using the app';
  static const allowAllTheTimeFor =
      'Allow all the time, for background updates';

  // ---- Photo crop ------------------------------------------------------------

  static const moveAndScale = 'Move and scale';
  static const usePhoto = 'Use photo';
  static const thatPhotoCouldnTBe =
      'That photo couldn\'t be opened. Try another one.';
  static const dragToMovePinchTo = 'Drag to move. Pinch to zoom.';

  // ---- Settings --------------------------------------------------------------

  static const editNameAndPhoto = 'Edit name and photo';
  static const yourGroups = 'Your groups';
  static const locationSharing = 'Location sharing';
  static const shareMyLocation = 'Share my location';
  static const yourFriendsCanSeeWhere = 'Your friends can see where you are';
  static const pausedFriendsSeeYourLast = 'Paused: friends see your last spot';
  static const map = 'Map';
  static const connection = 'Connection';
  static const noGroupServerYet = 'No group server yet';
  static const reconnect = 'Reconnect';
  static const advanced = 'Advanced';
  static const youShouldnTNeedThese = 'You shouldn\'t need these';
  static const account = 'Account';
  static const publishesTo = 'Publishes to';
  static const nothingYet = 'Nothing yet';
  static const noneYourGroupIsnT = 'None: your group isn\'t set up';
  static String sOwn(Object? host, Object? name) => '${host} (${name}\'s own)';
  static const accountServerLabel = 'Your account\'s server';
  static const showMyLogin = 'Show my login';
  static const toUseThisAccountIn =
      'To use this account in the regular OwnTracks app';
  static const keepAlive = 'Keep-alive';
  static String seconds(Object? keepAliveSeconds) =>
      '${keepAliveSeconds} seconds';
  static const sendMyLocationNow = 'Send my location now';
  static const signOutOfThisPhone = 'Sign out of this phone';
  static const deleteMyAccount = 'Delete my account';
  static const flockWorksWithOwntracks = 'Flock · works with OwnTracks';
  static const connected = 'Connected';
  static const loading = 'Loading…';
  static const notInAGroupYet = 'Not in a group yet';
  static String waitingToJoin(Object? waiting) => '${waiting} waiting to join';
  static String waitingOnToLetYou(Object? pendingCount) =>
      'waiting on ${pendingCount} to let you in';
  static const showYourLogin = 'Show your login?';
  static const anyoneWithThisLoginCan =
      'Anyone with this login can see your group and appear as you. Only '
      'put it in your own apps.';
  static const show = 'Show';
  static const mode = 'Mode';
  static const host = 'Host';
  static const on = 'On';
  static const off = 'Off';
  static const usernameUserid = 'Username (UserID)';
  static const password = 'Password';
  static const deviceId = 'Device ID';
  static const publishTopic = 'Publish topic';
  static const yourLogin = 'Your login';
  static const enterTheseInTheOther =
      'Enter these in the other app. Only run one app at a time, or '
      'they\'ll fight over your spot on the map.';
  static const serverCertificate = 'Server certificate';
  static const thisServerUsesItsOwn =
      'This server uses its own certificate. The other app has to '
      'trust it: copy it into a file ending in .crt and install it '
      '(on iPhone also turn it on under Certificate Trust '
      'Settings).';
  static const copyCertificate = 'Copy certificate';
  static const deleteYourAccount = 'Delete your account?';
  static const youLeaveAllYourGroups =
      'You leave all your groups and stop sharing your location. Your '
      'history is gone within a few days. This can\'t be undone.';
  static const delete = 'Delete';
  static const signOut = 'Sign out?';
  static const thisPhoneStopsSharingYour =
      'This phone stops sharing your location and forgets your login. '
      'You can\'t sign back in to the same account, so you\'ll make a new '
      'one and ask to join your groups again.';
  static const signOut2 = 'Sign out';
  static const satellite = 'Satellite';
  static const streets = 'Streets';
  static const terrain = 'Terrain';
  static const dark = 'Dark';
  static const googleMaps = 'Google Maps';
  static const theFamiliarGoogleLookWith =
      'The familiar Google look, with satellite and terrain.';
  static const notAvailableInThisBuild =
      'Not available in this build (no Google Maps key).';
  static const openstreetmap = 'OpenStreetMap';
  static const noGoogleInvolvedSatellitePhotos =
      'No Google involved. Satellite photos come from Esri.';
  static const yourPhoto = 'Your photo';
  static const camera = 'Camera';
  static const library = 'Library';
  static String tracking3(Object? mode) => 'Tracking: ${mode}';
  static const joinOrStartAGroup = 'Join or start a group to start sharing.';
  static String isnTSetUpYet2(Object? name) => '${name} isn\'t set up yet.';
  static String setByFor(Object? mode, Object? leaderName, Object? name) =>
      '${mode} Set by ${leaderName} '
      'for ${name}.';

  // ---- Account server messages -----------------------------------------------

  static const couldnTReachTheServer =
      'Couldn\'t reach the server in this invite. Check your connection '
      'and try again.';
  static const thisInviteDoesnTMatch =
      'This invite doesn\'t match the server it points to, so it isn\'t '
      'safe to use. Ask for a new invite.';
  static const couldnTReachTheServer2 =
      'Couldn\'t reach the server. Check your connection and try again.';
  static String theServerHadAProblem(Object? statusCode) =>
      'The server had a problem (error ${statusCode}).';

  // ---- Location notification -------------------------------------------------

  static const sharingYourLocation = 'Sharing your location';
  static const yourFriendsCanSeeWhere2 = 'Your friends can see where you are.';

  // ---- Connection messages ---------------------------------------------------

  static const connectedEverythingLooksGood =
      'Connected! Everything looks good.';
  static String butItDoesWorkWith(Object? message, Object? value) =>
      '${message}\n\nBut it does work with ${value}.';
  static String foundYourServerButIt(Object? value) =>
      'Found your server (${value}), but it rejected the username or password.';
  static const aSelfSignedCertificateAllowed =
      'a self-signed certificate allowed';
  static const secureConnectionOnPort8883 = 'secure connection on port 8883';
  static const secureConnectionOnPort88832 =
      'secure connection on port 8883 with a self-signed certificate';
  static const port1883WithoutASecure = 'port 1883 without a secure connection';
  static const websocketsOnPort443 = 'WebSockets on port 443';
  static const theServerRejectedTheUsername =
      'The server rejected the username or password.';
  static const theServerRejectedThisPhone =
      'The server rejected this phone\'s ID. Try changing your name slightly.';
  static const theServerIsUpBut =
      'The server is up but not accepting connections right now.';
  static const theServerDoesnTSpeak =
      'The server doesn\'t speak a compatible MQTT version.';
  static String couldnTConnectTo(Object? host, Object? port) =>
      'Couldn\'t connect to ${host}:${port}.';
  static String theServerAtDidnT(Object? host, Object? port) =>
      'The server at ${host}:${port} didn\'t answer. Check the address and port.';
  static const theServerSSecurityCertificate =
      'The server\'s security certificate is for a different '
      'address. Use the server\'s name exactly as its certificate '
      'shows it, not its IP address.';
  static const theServerSSecurityCertificate2 =
      'The server\'s security certificate isn\'t trusted by this phone '
      '(it\'s probably self-signed). Turn on "Allow self-signed certificate" '
      'under More options.';
  static String aSecureConnectionCouldnT(Object? port) =>
      'A secure connection couldn\'t be set up. If your server doesn\'t use TLS on '
      'port ${port}, turn "Secure connection" off.';
  static String couldnTFindAServer(Object? host) =>
      'Couldn\'t find a server called "${host}". Check the spelling.';
  static String foundTheServerButNothing(Object? port) =>
      'Found the server, but nothing is listening on port ${port}. Check the port.';
  static const thisPhoneLooksOfflineCheck =
      'This phone looks offline. Check your internet connection.';
  static const theServerTookTooLong =
      'The server took too long to answer. Check the address and port.';
  static String couldnTReach(Object? host, Object? port) =>
      'Couldn\'t reach ${host}:${port}.';
  static String somethingWentWrongConnecting(Object? error) =>
      'Something went wrong connecting: ${error}';

  // ---- History server messages -----------------------------------------------

  static const locationHistoryIsnTSet = 'Location history isn\'t set up yet.';
  static const couldnTReachTheHistory =
      'Couldn\'t reach the history server. Check your connection.';
  static const theHistoryServerRejectedThe =
      'The history server rejected the login.';
  static const youCanOnlySeeHistory =
      'You can only see history for people in your groups.';
  static const theHistoryServerAddressLooks =
      'The history server address looks wrong (got "not found").';
  static String theHistoryServerHadA(Object? statusCode) =>
      'The history server had a problem (error ${statusCode}).';
  static const theHistoryServerSentSomething =
      'The history server sent something unexpected.';

  // ---- Joining messages ------------------------------------------------------

  static const thatIsnTAnInvite =
      'That isn\'t an invite. Ask whoever runs the group to send it '
      'with Share in Flock, then paste the whole message here.';
  static const thisInviteIsForA =
      'This invite is for a different server than your account. To '
      'switch, sign out in Settings first.';
  static const enterYourNameFirst = 'Enter your name first.';

  // ---- Times and distances ---------------------------------------------------

  static const justNow = 'Just now';
  static String minAgo(Object? inMinutes) => '${inMinutes} min ago';
  static String hAgo(Object? inHours) => '${inHours} h ago';
  static String today(Object? hm) => 'Today ${hm}';
  static String yesterday(Object? hm) => 'Yesterday ${hm}';
  static String km(Object? meters) => '${meters} km';
  static const n1Min = '<1 min';
  static String min(Object? inMinutes) => '${inMinutes} min';
  static String hMin(Object? h, Object? m) => '${h} h ${m} min';
  static const today2 = 'Today';
  static const yesterday2 = 'Yesterday';

  // ---- Avatar ----------------------------------------------------------------

  static const showPhoto = 'Show photo';

  // ---- Connection form -------------------------------------------------------

  static const eGTrackingExampleCom = 'e.g. tracking.example.com';
  static const username = 'Username';
  static const theLoginYourGroupShares = 'The login your group shares';
  static const secureConnection = 'Secure connection';
  static const leaveOnUnlessYourServer =
      'Leave on unless your server says otherwise';
  static const almostAlwaysOwntracks = 'Almost always "owntracks"';
  static const connectOverWebsockets = 'Connect over WebSockets';
  static const allowSelfSignedCertificate = 'Allow self-signed certificate';
  static const onlyIfYouRunYour = 'Only if you run your own certificates';
  static const useTheseSettings = 'Use these settings';

  // ---- Map -------------------------------------------------------------------

  static const esriMaxarEarthstarGeographicsAnd =
      'Esri, Maxar, Earthstar Geographics, and the GIS User Community';
  static const openstreetmapContributors = 'OpenStreetMap contributors';

  // ---- History joystick ------------------------------------------------------

  static const historyJoystick = 'History joystick';
  static const dragLeftForEarlierRight =
      'Drag left for earlier, right for later';
  static const earlier = 'Earlier';
  static const later = 'Later';

  // ---- Small words ------------------------------------------------------

  static String memberCount(int n) => n == 1 ? '1 member' : '$n members';
  static const unknownServer = 'unknown';
  static const you = 'you';
  static const tls = 'TLS';
  static const historyAddressHint = 'https://… of an OwnTracks Recorder';

  // ---- Your tracking level and switching groups -----------------------------
  static String groupDefault(Object? mode) => 'Group default ($mode)';
  static String groupDefaultBy(Object? leader, Object? group) =>
      'Set by $leader for $group';
  static const yourTracking = 'Your tracking';
  static const changeGroupDefault = 'Change the group default';
  static const showGroup = 'Show group';
  static String liveIn(Object? status, Object? group) => '$status · $group';
}
