import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/controller.dart';
import 'ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Bootstrap());
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});
  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  late Future<VaultController> future = VaultController.create();
  @override
  Widget build(BuildContext context) => FutureBuilder<VaultController>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return ProviderScope(
          overrides: [vaultProvider.overrideWithValue(snapshot.data!)],
          child: SafeVaultApp(controller: snapshot.data!),
        );
      }
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      size: 64,
                      color: Color(0xff17645D),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Safe Vault',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (!snapshot.hasError)
                      const CircularProgressIndicator()
                    else ...[
                      const Text(
                        'Your vault could not be opened. No data has been erased.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Check available storage and restart the app. Keep your app data intact so your records can be recovered.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () => setState(() {
                          future = VaultController.create();
                        }),
                        child: const Text('Retry'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
