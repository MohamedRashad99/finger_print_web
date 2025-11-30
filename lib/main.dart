import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(MyApp());

// dvdsdvdsds
}

class MyApp extends StatelessWidget {
  // Toggle this to false to call a real server instead of local simulation.
  static const bool simulateServer = true;

  // If not simulating, set your API base here:
  static const String apiBase = 'https://your-server.com';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter WebAuthn Demo',
      home: Scaffold(
        appBar: AppBar(title: const Text('Fingerprint (WebAuthn) Demo')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: AuthDemoPage(simulateServer: simulateServer, apiBase: apiBase),
        ),
      ),
    );
  }
}

class AuthDemoPage extends StatefulWidget {
  final bool simulateServer;
  final String apiBase;
  const AuthDemoPage({required this.simulateServer, required this.apiBase, Key? key}) : super(key: key);

  @override
  State<AuthDemoPage> createState() => _AuthDemoPageState();
}

class _AuthDemoPageState extends State<AuthDemoPage> {
  String _log = '';
  final _usernameController = TextEditingController(text: 'mohamed');

  void _appendLog(String s) {
    setState(() {
      _log = '$_log\n$s';
    });
  }

  // Helper: call JS function that returns a Promise
  Future<Map<String, dynamic>> _callJs(String fnName, Map<String, dynamic> arg) async {
    final completer = Completer<Map<String, dynamic>>();
    final jsArg = js.JsObject.jsify(arg);
    final promise = js.context.callMethod(fnName, [jsArg]);
    try {
      final result = await promise.asFuture();
      final jsonStr = js.context['JSON'].callMethod('stringify', [result]);
      completer.complete(json.decode(jsonStr) as Map<String, dynamic>);
    } catch (err) {
      completer.completeError(err ?? 'JS error');
    }
    return completer.future;
  }
  // Simulated server helpers (store in localStorage)
  String _storageKeyForUser(String username) => 'webauthn_demo_$username';

  Map<String, dynamic>? _loadSimulatedRegistration(String username) {
    final raw = html.window.localStorage[_storageKeyForUser(username)];
    if (raw == null) return null;
    return json.decode(raw) as Map<String, dynamic>;
  }

  void _saveSimulatedRegistration(String username, Map<String, dynamic> data) {
    html.window.localStorage[_storageKeyForUser(username)] = json.encode(data);
  }

  // Generate a random challenge (base64url)
  String _randomBase64Url(int len) {
    final bytes = List<int>.generate(len, (_) => DateTime.now().microsecond % 256);
    // not cryptographically strong in this demo; server should use CSPRNG
    final encoded = base64Url.encode(bytes).replaceAll('=', '');
    return encoded;
  }

  Future<void> _register() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) return;
    _appendLog('Start registration for $username');

    try {
      Map<String, dynamic> options;
      if (widget.simulateServer) {
        // Simulate server creation options
        final userId = base64UrlEncodeUtf8('user-$username'); // simple user id
        options = {
          'challenge': _randomBase64Url(32),
          'rp': {'name': 'DemoApp', 'id': html.window.location.hostname},
          'user': {'id': userId, 'name': username, 'displayName': username},
          'pubKeyCredParams': [
            {'type': 'public-key', 'alg': -7} // ES256
          ],
          'timeout': 60000,
          'attestation': 'none',
          // authenticatorSelection will be enforced in JS to platform + userVerification required
        };
      } else {
        final res = await http.post(Uri.parse('${widget.apiBase}/webauthn/register/options'),
            headers: {'content-type': 'application/json'},
            body: json.encode({'username': username}));
        if (res.statusCode != 200) throw Exception('Server options failed: ${res.body}');
        options = json.decode(res.body) as Map<String, dynamic>;
      }

      _appendLog('Calling navigator.credentials.create() — biometric prompt should appear');
      final attestation = await _callJs('webauthnCreate', options);

      _appendLog('Got attestation, sending to server (or simulate store)');

      if (widget.simulateServer) {
        // store minimal info: credentialId
        final stored = {'credentialId': attestation['rawId'], 'registeredAt': DateTime.now().toIso8601String()};
        _saveSimulatedRegistration(username, stored);
        _appendLog('Simulated registration saved locally (credentialId).');
      } else {
        final verifyRes = await http.post(Uri.parse('${widget.apiBase}/webauthn/register/verify'),
            headers: {'content-type': 'application/json'}, body: json.encode(attestation));
        if (verifyRes.statusCode != 200) throw Exception('Register verify failed: ${verifyRes.body}');
        _appendLog('Server verified and stored credential.');
      }
    } catch (e, st) {
      _appendLog('Registration error: $e');
      print(st);
    }
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) return;
    _appendLog('Start authentication for $username');

    try {
      Map<String, dynamic> options;
      if (widget.simulateServer) {
        final stored = _loadSimulatedRegistration(username);
        if (stored == null) {
          _appendLog('No credential found for user locally. Register first.');
          return;
        }
        options = {
          'challenge': _randomBase64Url(32),
          'timeout': 60000,
          'rpId': html.window.location.hostname,
          'allowCredentials': [
            {'type': 'public-key', 'id': stored['credentialId']}
          ],
          'userVerification': 'required'
        };
      } else {
        final res = await http.post(Uri.parse('${widget.apiBase}/webauthn/auth/options'),
            headers: {'content-type': 'application/json'},
            body: json.encode({'username': username}));
        if (res.statusCode != 200) throw Exception('Server auth options failed: ${res.body}');
        options = json.decode(res.body) as Map<String, dynamic>;
      }

      _appendLog('Calling navigator.credentials.get() — biometric prompt should appear');
      final assertion = await _callJs('webauthnGet', options);

      if (widget.simulateServer) {
        // In real server you must verify signature. Here we treat success of navigator.credentials.get as OK.
        _appendLog('Assertion success — treated as authenticated (simulation).');
      } else {
        final verifyRes = await http.post(Uri.parse('${widget.apiBase}/webauthn/auth/verify'),
            headers: {'content-type': 'application/json'}, body: json.encode(assertion));
        if (verifyRes.statusCode != 200) throw Exception('Auth verify failed: ${verifyRes.body}');
        _appendLog('Server verified assertion — authenticated.');
      }
    } catch (e, st) {
      _appendLog('Authentication error: $e');
      print(st);
    }
  }

  // helper to encode UTF8 string to base64url (simple)
  static String base64UrlEncodeUtf8(String s) {
    final bytes = utf8.encode(s);
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('Demo: register platform authenticator (fingerprint/Windows Hello) and login'),
        const SizedBox(height: 12),
        TextField(controller: _usernameController, decoration: const InputDecoration(labelText: 'Username')),
        const SizedBox(height: 12),
        Row(
          children: [
            ElevatedButton(onPressed: _register, child: const Text('Register Fingerprint')),
            const SizedBox(width: 12),
            ElevatedButton(onPressed: _login, child: const Text('Login with Fingerprint')),
          ],
        ),
        const SizedBox(height: 18),
        Expanded(
          child: SingleChildScrollView(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.black12,
              child: Text(
                _log,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ),
        )
      ],
    );
  }
}
