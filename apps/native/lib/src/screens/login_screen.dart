import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  Future<void> _login() async {
    setState(() { _busy = true; _error = null; });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on AuthException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Connexion impossible. Vérifiez votre réseau et réessayez.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Brand(),
                const SizedBox(height: 14),
                Text('Connectez-vous à votre espace MINE-ME.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white70)),
                const SizedBox(height: 32),
                TextField(controller: _email, keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(labelText: 'Adresse e-mail')),
                const SizedBox(height: 14),
                TextField(controller: _password, obscureText: _obscure,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _busy ? null : _login(),
                  decoration: InputDecoration(labelText: 'Mot de passe',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off))),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: const TextStyle(color: Color(0xFFFF8A80))),
                ],
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: _busy ? null : _login,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Se connecter'),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Les inscriptions et le parrainage se font depuis le portail MINE-ME.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 38, height: 38, alignment: Alignment.center,
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFADFF65)), borderRadius: BorderRadius.circular(10)),
      child: const Text('M', style: TextStyle(color: Color(0xFFADFF65), fontWeight: FontWeight.w900))),
    const SizedBox(width: 12),
    const Text('MINE-ME', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: 3)),
  ]);
}
