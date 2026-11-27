import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/device_service.dart';
import '../services/native_mining_controller.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _client = Supabase.instance.client;
  late final NativeMiningController _mining;

  bool _busy = true;
  String? _error;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _devices = [];
  BigInt _availableXmr = BigInt.zero;
  BigInt _heldXmr = BigInt.zero;
  bool _rewardLedgerAvailable = true;
  List<Map<String, dynamic>> _diagnosticEvents = [];

  @override
  void initState() {
    super.initState();
    _mining = NativeMiningController(_client)..addListener(_onMiningChanged);
    _load();
  }

  void _onMiningChanged() {
    if (!mounted) return;
    setState(() {
      if (_mining.errorMessage != null) _error = _mining.errorMessage;
    });
  }

  @override
  void dispose() {
    _mining.removeListener(_onMiningChanged);
    _mining.dispose();
    super.dispose();
  }

  BigInt _xmrToAtomic(dynamic value) {
    final text = value.toString();
    if (!RegExp(r'^\d+(?:\.\d{1,12})?$').hasMatch(text)) return BigInt.zero;
    final parts = text.split('.');
    final fraction = (parts.length > 1 ? parts[1] : '').padRight(12, '0');
    return BigInt.parse(parts[0]) * BigInt.from(1000000000000) +
        BigInt.parse(fraction.isEmpty ? '0' : fraction);
  }

  String _formatXmr(BigInt atomic) {
    final unit = BigInt.from(1000000000000);
    final whole = atomic ~/ unit;
    final fraction = (atomic % unit).toString().padLeft(12, '0');
    return '$whole.$fraction';
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('Session expirée.');

      final profile = await _client.from('profiles')
          .select('display_name, referral_code, role, account_status, consent_version, consented_at')
          .eq('id', user.id).single();

      final devices = await _client.from('devices')
          .select('id, label, worker_code, platform_family, status, intensity_percent, last_seen_at')
          .eq('user_id', user.id).order('created_at');

      var diagnosticEvents = <Map<String, dynamic>>[];
      try {
        final deviceIds = List<Map<String, dynamic>>.from(devices)
            .map((device) => device['id'] as String)
            .toList();
        if (deviceIds.isNotEmpty) {
          final events = await _client.from('device_events')
              .select('device_id, event_type, details, created_at')
              .inFilter('device_id', deviceIds)
              .order('created_at', ascending: false)
              .limit(12);
          diagnosticEvents = List<Map<String, dynamic>>.from(events);
        }
      } catch (_) {
        // Diagnostics are optional and must not block account/device access.
      }

      var available = BigInt.zero;
      var held = BigInt.zero;
      var rewardLedgerAvailable = true;
      try {
        final rewardRows = await _client.from('member_reward_ledger')
            .select('amount, status').eq('member_id', user.id);
        for (final row in rewardRows) {
          final amount = _xmrToAtomic(row['amount']);
          if (row['status'] == 'available') available += amount;
          if (row['status'] == 'held') held += amount;
        }
      } catch (_) {
        // The reward migration is deployed separately after review. Do not
        // block sign-in, device management or safe client installation while
        // the ledger schema is not yet present in the linked project.
        rewardLedgerAvailable = false;
      }

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _devices = List<Map<String, dynamic>>.from(devices);
        _diagnosticEvents = diagnosticEvents;
        _availableXmr = available;
        _heldXmr = held;
        _rewardLedgerAvailable = rewardLedgerAvailable;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveIntensity(String deviceId, int value) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('Session expirée.');
      await _client.from('devices').update({'intensity_percent': value})
          .eq('id', deviceId).eq('user_id', user.id);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      await _load();
    }
  }

  Future<void> _startMining(Map<String, dynamic> device) async {
    await _mining.start(
      device['id'] as String,
      intensityPercent: (device['intensity_percent'] as num?)?.toInt() ?? 20,
    );
  }

  Future<void> _enroll() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final deviceId = await DeviceService(_client).enroll();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Appareil associé avec succès · ${deviceId.substring(0, 8).toUpperCase()}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Association impossible : $error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async => _client.auth.signOut();

  @override
  Widget build(BuildContext context) {
    final name = (_profile?['display_name'] as String?) ?? 'Membre';
    return Scaffold(
      appBar: AppBar(
        title: const Text('MINE-ME',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
        actions: [
          IconButton(
            tooltip: 'Déconnexion',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            Text('Bonjour, $name',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              )),
            const SizedBox(height: 6),
            const Text('Votre espace membre MINE-ME',
              style: TextStyle(color: Colors.white60)),
            const SizedBox(height: 24),
            _statusCard(),
            const SizedBox(height: 12),
            _rewardCard(),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Mes appareils', style: Theme.of(context).textTheme.titleLarge),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
            ),
            if (_busy && _devices.isEmpty)
              const Center(child: Padding(
                padding: EdgeInsets.all(30),
                child: CircularProgressIndicator(),
              )),
            ..._devices.map(_deviceCard),
            _diagnosticsCard(),
            if (!_busy && _devices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text('Aucun appareil associé à ce compte.',
                  style: TextStyle(color: Colors.white60)),
              ),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _enroll,
              icon: const Icon(Icons.add_to_home_screen),
              label: const Text('Associer cet appareil'),
            ),
            const SizedBox(height: 18),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Color(0xFFFF8A80))),
            _referralCard(),
            const SizedBox(height: 24),
            const Text(
              'Le minage ne démarre qu’après validation du serveur, du compte, du consentement et de la pause globale. Sur Android, une notification persistante accompagne chaque session active.',
              style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _diagnosticsCard() {
    String eventLabel(String event) {
      const labels = {
        'started': 'Démarrage demandé',
        'session_requested': 'Demande de session envoyée',
        'session_http_error': 'Échec de l’API de session',
        'session_authorized': 'Session autorisée',
        'gateway_connected': 'Passerelle connectée',
        'gateway_ready': 'Passerelle authentifiée',
        'gateway_error': 'Erreur de passerelle',
        'pool_job_received': 'Travail reçu du pool',
        'randomx_initializing': 'Initialisation RandomX',
        'randomx_ready': 'Moteur RandomX prêt',
        'randomx_error': 'Erreur RandomX',
        'share_submitted': 'Part transmise',
        'share_accepted': 'Part acceptée par le pool',
        'share_rejected': 'Part refusée par le pool',
        'worker_disconnected': 'Déconnexion du mineur',
        'paused': 'Minage mis en pause',
        'stopped': 'Minage arrêté',
        'error': 'Erreur',
      };
      return labels[event] ?? event;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('TRAÇABILITÉ DU MINAGE',
                    style: TextStyle(
                      color: Color(0xFFADFF65),
                      fontSize: 11,
                      letterSpacing: 1.3,
                    )),
                ),
                IconButton(
                  tooltip: 'Actualiser les diagnostics',
                  onPressed: _busy ? null : _load,
                  icon: const Icon(Icons.refresh, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Historique des étapes, connexions et erreurs récentes de vos appareils.',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 10),
            if (_diagnosticEvents.isEmpty)
              const Text(
                'Aucun événement de minage enregistré pour le moment.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              )
            else
              ..._diagnosticEvents.take(8).map((event) {
                final details = event['details'] is Map
                    ? Map<String, dynamic>.from(event['details'] as Map)
                    : <String, dynamic>{};
                final eventType = event['event_type'] as String? ?? 'event';
                final trace = details['trace_id']?.toString();
                final code = details['error_code']?.toString();
                final status = details['http_status']?.toString();
                final createdAt = DateTime.tryParse(
                  event['created_at']?.toString() ?? '',
                )?.toLocal();
                final time = createdAt == null
                    ? 'Date inconnue'
                    : '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')} '
                      '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}:${createdAt.second.toString().padLeft(2, '0')}';
                final isError = eventType.contains('error') ||
                    eventType == 'session_http_error';
                return Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isError ? Icons.error_outline : Icons.check_circle_outline,
                        size: 16,
                        color: isError ? Colors.orangeAccent : const Color(0xFFADFF65),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(eventLabel(eventType),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            Text(
                              [
                                time,
                                if (code != null) code,
                                if (status != null) 'HTTP $status',
                                if (trace != null) 'Trace ${trace.length > 10 ? trace.substring(0, 10) : trace}',
                              ].join(' · '),
                              style: const TextStyle(color: Colors.white54, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _statusCard() {
    final status = _profile?['account_status'] ?? 'Vérification…';
    final consent = _profile?['consent_version'] == '2026-11-19-v1' &&
        _profile?['consented_at'] != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ÉTAT DU COMPTE',
              style: TextStyle(color: Color(0xFFADFF65), fontSize: 11, letterSpacing: 1.5)),
            const SizedBox(height: 10),
            Text(status == 'active' ? 'Compte actif' : 'Compte : $status',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(consent ? Icons.verified : Icons.warning_amber, size: 16,
                  color: consent ? const Color(0xFFADFF65) : Colors.orangeAccent),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  consent ? 'Consentement actuel confirmé' : 'Consentement actuel à vérifier',
                  style: const TextStyle(color: Colors.white70),
                )),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Le démarrage nécessite l’autorisation du serveur MINE-ME et le respect des limites de sécurité.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rewardCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('RÉCOMPENSES · WALLET CENTRAL HASHVAULT',
            style: TextStyle(color: Color(0xFFADFF65), fontSize: 11, letterSpacing: 1.2)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Disponible', style: TextStyle(color: Colors.white60, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('${_formatXmr(_availableXmr)} XMR',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ],
              )),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('En réserve', style: TextStyle(color: Colors.white60, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('${_formatXmr(_heldXmr)} XMR',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ],
              )),
            ],
          ),
          const SizedBox(height: 12),
          if (!_rewardLedgerAvailable)
            const Text('Le registre des récompenses sera disponible après la mise à jour sécurisée du serveur.',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 11)),
          const Text(
            'Tous les membres contribuent au même wallet HashVault. Ces montants sont des crédits internes calculés à partir des parts acceptées et des paiements centraux confirmés. Aucun wallet individuel n’est créé.',
            style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    ),
  );

  Widget _deviceCard(Map<String, dynamic> device) {
    final deviceId = device['id'] as String;
    final active = _mining.activeDeviceId == deviceId;
    final running = active && _mining.state == NativeMiningState.running;
    final busy = active && (
      _mining.state == NativeMiningState.authorising ||
      _mining.state == NativeMiningState.connecting ||
      _mining.state == NativeMiningState.initialising ||
      _mining.state == NativeMiningState.stopping
    );
    final blocked = device['status'] == 'blocked';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF263629),
                child: Icon(Icons.devices, color: Color(0xFFADFF65)),
              ),
              title: Text((device['label'] as String?) ?? device['worker_code'] as String),
              subtitle: Text('${device['worker_code']} · ${device['platform_family'] ?? 'Appareil'}'),
              trailing: Text((device['status'] as String?) ?? '—',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
            if (!blocked && !active)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Intensité CPU',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                        const Spacer(),
                        Text('${device['intensity_percent'] ?? 20} %',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      ],
                    ),
                    Slider(
                      value: ((device['intensity_percent'] as num?)?.toDouble() ?? 20)
                          .clamp(1, 80).toDouble(),
                      min: 1,
                      max: 80,
                      divisions: 79,
                      onChanged: (value) => setState(
                        () => device['intensity_percent'] = value.round(),
                      ),
                      onChangeEnd: (value) => _saveIntensity(deviceId, value.round()),
                    ),
                  ],
                ),
              ),
            if (active && running)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.speed, size: 16, color: Color(0xFFADFF65)),
                    const SizedBox(width: 7),
                    Text('${_mining.hashesPerSecond.toStringAsFixed(1)} H/s',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text(
                      'Shares : ${_mining.acceptedShares} acceptées · ${_mining.rejectedShares} refusées',
                      style: const TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ],
                ),
              ),
            if (active && _mining.randomXMode != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _mining.randomXMode == 'fast'
                    ? 'RandomX rapide · dataset complet'
                    : 'RandomX léger · mémoire réduite',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Row(
                children: [
                  if (running) ...[
                    Expanded(child: OutlinedButton.icon(
                      onPressed: _mining.pause,
                      icon: const Icon(Icons.pause),
                      label: const Text('Pause'),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: FilledButton.tonalIcon(
                      onPressed: _mining.stop,
                      icon: const Icon(Icons.stop),
                      label: const Text('Arrêter'),
                    )),
                  ] else ...[
                    Expanded(child: FilledButton.icon(
                      onPressed: blocked || busy ? null : () => _startMining(device),
                      icon: busy
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.play_arrow),
                      label: Text(busy ? 'Préparation…' : 'Démarrer le minage'),
                    )),
                  ],
                ],
              ),
            ),
            if (active && _mining.errorMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(_mining.errorMessage!,
                  style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _referralCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('VOTRE CODE DE PARRAINAGE',
            style: TextStyle(color: Color(0xFFADFF65), fontSize: 11, letterSpacing: 1.3)),
          const SizedBox(height: 10),
          SelectableText((_profile?['referral_code'] as String?) ?? '—',
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: 2)),
        ],
      ),
    ),
  );
}
