import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const _consentVersion = '2026-11-19-v1';
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _referralCode = TextEditingController();
  bool _consent = false;
  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;
  String? _message;

  Future<void> _register() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });

    if (_name.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        _password.text.length < 8 ||
        _referralCode.text.trim().isEmpty) {
      setState(() {
        _busy = false;
        _error = 'Veuillez remplir tous les champs. Le mot de passe doit contenir au moins 8 caractères.';
      });
      return;
    }
    if (!_consent) {
      setState(() {
        _busy = false;
        _error = 'Vous devez lire et accepter les conditions de participation pour continuer.';
      });
      return;
    }

    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
        emailRedirectTo: '${MineMeConfig.apiBaseUrl}/auth/callback',
        data: {
          'display_name': _name.text.trim(),
          'referral_code': _referralCode.text.trim().toUpperCase(),
          'consent_to_compute': true,
          'consent_version': _consentVersion,
        },
      );

      if (!mounted) return;
      if (response.session != null) {
        // The root auth-state listener will open the member dashboard.
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        setState(() {
          _message = 'Votre demande a été enregistrée. Consultez votre boîte e-mail pour confirmer votre adresse. Le minage reste désactivé.';
        });
      }
    } on AuthException catch (exception) {
      if (!mounted) return;
      final details = exception.message.toLowerCase();
      if (details.contains('referral') || details.contains('invitation')) {
        setState(() => _error = 'Ce code d’invitation est invalide, expiré ou déjà utilisé. Vérifiez le code reçu.');
      } else if (details.contains('consent') || details.contains('acceptance')) {
        setState(() => _error = 'L’acceptation des conditions de participation est nécessaire pour créer un compte.');
      } else if (details.contains('already registered') || details.contains('user already registered')) {
        setState(() => _error = 'Un compte existe déjà avec cette adresse e-mail. Connectez-vous plutôt.');
      } else {
        setState(() => _error = 'Impossible de créer votre compte pour le moment. Vérifiez vos informations et réessayez.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Service momentanément indisponible. Vérifiez votre connexion et réessayez.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showTerms() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conditions de participation'),
        content: const SingleChildScrollView(
          child: Text(
            'Participation volontaire\n'
            'Votre appareil ne doit effectuer aucun calcul pour MINE-ME sans votre accord explicite. Vous pouvez arrêter votre participation à tout moment.\n\n'
            'Utilisation des ressources\n'
            'Lorsque le module sera activé, une partie des ressources de calcul de votre appareil pourra être utilisée. Cela peut augmenter l’utilisation du processeur, la consommation d’énergie et de données, la chaleur, le bruit des ventilateurs ainsi que l’usure de l’appareil ou de sa batterie. Le système peut limiter ou suspendre les tâches en arrière-plan.\n\n'
            'Intensité et arrêt\n'
            'Vous contrôlez l’intensité de calcul et pouvez mettre en pause ou arrêter à tout moment. Les limites de sécurité de la plateforme peuvent réduire la charge maximale autorisée.\n\n'
            'Propriété des produits du minage\n'
            'Tous les produits du minage appartiennent à la plateforme MINE-ME. Les participants ne reçoivent aucun partage de revenus, aucune rémunération liée à leurs shares et aucun solde individuel retirable. Les statistiques par appareil sont des données internes uniquement.\n\n'
            'Mesures vérifiables\n'
            'Les shares acceptées doivent provenir du pool ou d’une source de vérification serveur. Les estimations locales ne constituent pas une preuve de revenu. Aucune rentabilité n’est garantie.\n\n'
            'Version des conditions : 2026-11-19-v1.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _referralCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Créer un compte')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            children: [
              const Text('Rejoindre MINE-ME',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('L’inscription nécessite un code d’invitation valide.'),
              const SizedBox(height: 24),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                decoration: const InputDecoration(labelText: 'Nom affiché'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Adresse e-mail'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Mot de passe (8 caractères minimum)',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _referralCode,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Code d’invitation / parrainage'),
                onChanged: (value) {
                  final normalized = value.toUpperCase();
                  if (value != normalized) {
                    _referralCode.value = TextEditingValue(
                      text: normalized,
                      selection: TextSelection.collapsed(offset: normalized.length),
                    );
                  }
                },
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF111923),
                  border: Border.all(color: const Color(0xFF273440)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _consent,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('J’ai lu et j’accepte les conditions de participation.'),
                      onChanged: (value) => setState(() => _consent = value ?? false),
                    ),
                    const Text(
                      'Le calcul ne démarrera pas sans activation explicite. Lorsqu’il sera disponible, il pourra utiliser une partie des ressources de votre appareil et augmenter la consommation électrique, la chaleur, le bruit et l’usure.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    TextButton.icon(
                      onPressed: _showTerms,
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Lire les conditions complètes'),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: const TextStyle(color: Color(0xFFFF8A80))),
              ],
              if (_message != null) ...[
                const SizedBox(height: 14),
                Text(_message!, style: const TextStyle(color: Color(0xFFADFF65))),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _register,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Créer mon compte'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('J’ai déjà un compte — Se connecter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
