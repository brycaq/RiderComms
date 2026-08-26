import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../permissions.dart';
import '../session_state.dart';
import 'session_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _nameController = TextEditingController(text: 'My Session');
  bool _busy = false;

  /// Requests permissions, then runs [action]. Shows a SnackBar instead of
  /// failing silently if permissions are missing or the native call throws -
  /// this is what was missing before: an unguarded await meant a thrown
  /// PlatformException killed the whole onPressed handler before it ever
  /// reached Navigator.push, so the button looked like it did nothing.
  Future<void> _runWithPermissions(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      final missing = await requestDiscoveryPermissions();
      if (missing.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Missing permissions: ${missing.map((p) => p.toString().split('.').last).join(', ')}. '
                'Enable them in system settings to host or join.',
              ),
              action: SnackBarAction(label: 'Settings', onPressed: openAppSettings),
            ),
          );
        }
        return;
      }
      await action();
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SessionScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start session: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Intercom')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.podcasts, size: 64),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Session name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('Host a session'),
                onPressed: _busy
                    ? null
                    : () => _runWithPermissions(() => session.hostSession(
                        _nameController.text.trim().isEmpty ? 'Session' : _nameController.text.trim())),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.search),
                label: const Text('Join a nearby session'),
                onPressed: _busy ? null : () => _runWithPermissions(session.joinNearbySession),
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}
