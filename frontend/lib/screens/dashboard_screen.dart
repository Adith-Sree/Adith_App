import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/focus_session.dart';
import '../models/analytics_response.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../widgets/force_stop_button.dart';
import '../widgets/custom_charts.dart';
import '../widgets/cyber_terminal.dart';
import '../widgets/discipline_chart.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  // 1. Controllers & Services
  final ApiService _apiService = ApiService();
  final TextEditingController _goalController = TextEditingController();

  // 2. Navigation State Variables
  String _currentTab = 'Dashboard'; // 'Dashboard', 'Sessions', 'Goals', 'Analytics', 'Settings'

  // 3. Active Session Variables
  bool _isSessionActive = false;
  bool _isIntercepted = false;
  String _aiStreamedMessage = "";
  bool _isLoading = false;
  bool _isForceStopping = false;

  // Tracks the real DB row id of the currently active session.
  // Null when no session is running.
  int? _activeSessionId;
  DateTime? _sessionTargetEndTime;

  // ── LIVE Analytics State ──────────────────────────────────────────────────
  // Replaces all hardcoded metric variables.
  // Initialised to empty() so the UI starts at 0 before the first fetch.
  AnalyticsResponse _analyticsData = AnalyticsResponse.empty();
  bool _isAnalyticsLoading = false;

  // In-session UI-only metrics (not persisted, just for the timer screen UX)
  int _focusScore = 95;
  int _efficiency = 92;
  int _resistedCount = 0;
  int _completedBlocks = 0;

  // Customizable time and active timers
  int _duration = 120; // Committed duration in minutes
  int _secondsRemaining = 0; // Ticking remaining time
  Timer? _countdownTimer;
  Timer? _distractionTimer;

  // Real-time console logs
  final List<String> _activeLogs = [
    "[SYSTEM] Deep Work Broker kernel v1.0.4 loaded successfully.",
    "[MEMORY] Loaded ChromaDB historical vector database from directory: ./chroma_data",
    "[LOCKDOWN] Port 8000 online. Standby for focus contract commitments...",
    "[FIREWALL] Twitter.com, Youtube.com, Reddit.com marked as quarantine hosts.",
    "[MONITOR] Background metrics listener active. High-precision eye tracker connected.",
    "[STATUS] Focus state: NOMINAL. Ready to broker.",
  ];

  // Persistent task checklist (Goals tab) — fully synchronized with the database
  List<Map<String, dynamic>> _checklistTasks = [];
  bool _isGoalsLoading = false;

  final TextEditingController _localTaskController = TextEditingController();

  // 5. Theme Colors (Cyberpunk Dark Mode)
  final Color bgColor = const Color(0xFF09090C);
  final Color surfaceColor = const Color(0xFF14141A);
  final Color accentBlue = const Color(0xFF2962FF);
  final Color accentGreen = const Color(0xFF00E676);
  final Color accentRed = const Color(0xFFFF1744);
  final Color textMuted = Colors.grey[500]!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Fetch live score + graph + checklist goals on first render
    _refreshAnalytics();
    _loadGoals();
    // Request system notifications permission on mobile launch
    NotificationService().requestPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _distractionTimer?.cancel();
    _goalController.dispose();
    _localTaskController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      if (_isSessionActive && _sessionTargetEndTime != null) {
        final now = DateTime.now();
        if (now.isAfter(_sessionTargetEndTime!)) {
          // Timer naturally finished while backgrounded!
          _countdownTimer?.cancel();
          _distractionTimer?.cancel();
          _onSessionComplete();
        } else {
          // Adjust remaining seconds and continue ticking
          setState(() {
            _secondsRemaining = _sessionTargetEndTime!.difference(now).inSeconds;
          });
        }
      }
    }
  }

  // ── Checklist Goals Load ──────────────────────────────────────────────────
  Future<void> _loadGoals() async {
    if (!mounted) return;
    setState(() => _isGoalsLoading = true);
    final loaded = await _apiService.fetchGoals(userId: 1);
    if (!mounted) return;
    setState(() {
      _checklistTasks = loaded;
      _isGoalsLoading = false;
    });
  }

  // ── Analytics Refresh ─────────────────────────────────────────────────────
  Future<void> _refreshAnalytics() async {
    if (!mounted) return;
    setState(() => _isAnalyticsLoading = true);
    final data = await _apiService.fetchAnalytics(userId: 1);
    if (!mounted) return;
    setState(() {
      _analyticsData = data;
      _isAnalyticsLoading = false;
    });
  }

  // ==========================================
  // LOGIC & COUNTDOWN TIMERS
  // ==========================================
  void _startTimer(int minutes) {
    _countdownTimer?.cancel();
    _distractionTimer?.cancel();

    setState(() {
      _secondsRemaining = minutes * 60;
      _sessionTargetEndTime = DateTime.now().add(Duration(seconds: _secondsRemaining));
      _resistedCount = 0;
      _focusScore = 95;
      _efficiency = 92;
      _activeLogs.add("--------------------------------------------------");
      _activeLogs.add("[SYSTEM] focus contract signed. Goal: ${_goalController.text}");
      _activeLogs.add("[LOCKDOWN] Device interface LOCKED. Quitting penalty set to -25 points.");
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        // ── Timer expired naturally — register completion in the DB ──────────
        _countdownTimer?.cancel();
        _distractionTimer?.cancel();
        _onSessionComplete();
      }
    });

    // Start periodic distraction simulator
    final List<String> mockDistractions = [
      "[FIREWALL] Distraction blocked: Attempted to open Twitter.com. Cognitive broker resisted!",
      "[FIREWALL] Distraction blocked: Attempted to open YouTube.com. Gaze suppressed!",
      "[FIREWALL] Distraction blocked: Distracting Slack notification suppressed.",
      "[FIREWALL] Alert: Unscheduled calendar meeting request auto-responded (Deep Focus Mode).",
      "[MONITOR] Eye tracker validation: User gaze STABLE. Focus coefficient nominal.",
    ];

    _distractionTimer = Timer.periodic(const Duration(seconds: 12), (timer) {
      if (!mounted) return;
      if (!_isIntercepted && _isSessionActive) {
        setState(() {
          final String timeStr = DateTime.now().toIso8601String().substring(11, 19);
          final int index = timer.tick % mockDistractions.length;
          final String log = mockDistractions[index];
          _activeLogs.add("[$timeStr] $log");
          
          // Increment resisted count if it's a firewall block
          if (log.contains("blocked") || log.contains("suppressed")) {
            _resistedCount++;
          }
          
          // Fluctuate scores slightly to feel alive
          _focusScore = 93 + (timer.tick % 5);
          _efficiency = 90 + (timer.tick % 4);
        });
      }
    });
  }

  Future<void> _startSession() async {
    if (_goalController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must declare a goal first.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final newSession = FocusSession(
      goalDescription: _goalController.text,
      durationMinutes: _duration,
    );

    // startSession now returns the real DB session id (or null on failure)
    final sessionId = await _apiService.startSession(newSession);

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (sessionId != null) {
        _activeSessionId = sessionId; // store the real DB id
        _isSessionActive = true;
        _isIntercepted = false;
        _aiStreamedMessage = "";
        _startTimer(_duration);
        
        // Schedule completion alert and trigger instant start notification
        NotificationService().showInstantNotification(
          id: 777,
          title: "Focus Contract Locked 🔒",
          body: "Committed to '${_goalController.text}' for $_duration minutes.",
        );
        NotificationService().scheduleNotification(
          id: 888,
          title: "Focus Contract Fulfilled! 🛡️",
          body: "Your $_duration minute focus lock timer has reached zero.",
          secondsFromNow: _duration * 60,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Backend rejected the contract. Is the server running?',
            ),
          ),
        );
      }
    });
  }

  // Called when the countdown timer reaches zero
  Future<void> _onSessionComplete() async {
    final sid = _activeSessionId;
    
    // Cancel the scheduled timer alert and show instant success notification
    NotificationService().cancelNotification(888);
    NotificationService().showInstantNotification(
      id: 999,
      title: "Focus Contract Fulfilled! 🛡️",
      body: "Contract successfully completed. Awarded +25 discipline points.",
    );

    setState(() {
      _isSessionActive = false;
      _isIntercepted = false;
      _sessionTargetEndTime = null;
      _completedBlocks = math.min(_completedBlocks + 1, 3);
      _activeLogs.add("[SYSTEM] Focus contract timer expired!");
      _activeLogs.add("[BROKER] Registering completion with server...");
    });

    if (sid != null) {
      final result = await _apiService.completeSession(sid);
      if (!mounted) return;
      final reward = result?['reward'] as int? ?? 25;
      final newScore = result?['new_score'] as int?;
      setState(() {
        _activeSessionId = null;
        _activeLogs.add("[SYSTEM] Focus contract successfully completed! Reward: +$reward pts.");
        _activeLogs.add("[SYSTEM] Lock released. Session marked as SUCCESS.");
        if (newScore != null) {
          // Optimistically update the score display immediately
          _analyticsData = AnalyticsResponse(
            disciplineScore: newScore,
            graphPoints: _analyticsData.graphPoints,
            sessionHistory: _analyticsData.sessionHistory,
          );
        }
      });
    }
    // Refresh the full analytics data (graph + history) from the DB
    await _refreshAnalytics();
  }

  Future<void> _forceStop() async {
    setState(() => _isForceStopping = true);

    // Cancel scheduled countdown timer alarm on force quit
    NotificationService().cancelNotification(888);

    final sid = _activeSessionId ?? 1; // fall back to 1 for dev if id was lost
    final result = await _apiService.forceStopSession(sid);

    if (!mounted) return;

    setState(() {
      _isForceStopping = false;
      if (result != null) {
        _isSessionActive = false;
        _isIntercepted = false;
        _sessionTargetEndTime = null;
        _aiStreamedMessage = "";
        _activeSessionId = null;
        _countdownTimer?.cancel();
        _distractionTimer?.cancel();

        final penalty = result['penalty'] as int? ?? -25;
        
        NotificationService().showInstantNotification(
          id: 555,
          title: "Focus Contract Violated! 🚨",
          body: "Contract terminated early. Penalty applied: $penalty points.",
        );

        final newScore = result['new_score'] as int?;

        _activeLogs.add("[ALERT] Focus contract forcefully terminated! Penalty: $penalty pts.");
        _activeLogs.add("[SYSTEM] Lock released. Session marked as FAILED.");

        // Optimistic UI update — show exact server penalty immediately
        if (newScore != null) {
          _analyticsData = AnalyticsResponse(
            disciplineScore: newScore,
            graphPoints: _analyticsData.graphPoints,
            sessionHistory: _analyticsData.sessionHistory,
          );
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Contract terminated. Penalty: $penalty pts.',
            ),
            backgroundColor: const Color(0xFFFF1744),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to override the broker. Please try again.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
    });

    // Always refresh from DB after a force-stop attempt — even if it failed
    // (the session status on the server is the source of truth)
    if (result != null) await _refreshAnalytics();
  }

  // ==========================================
  // MASTER LAYOUT
  // ==========================================
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool showSidebar = screenWidth >= 1050;
    final bool showRightPanel = screenWidth >= 1300;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: bgColor,
      drawer: !showSidebar
          ? Drawer(
              backgroundColor: bgColor,
              child: _buildSidebar(isDrawer: true),
            )
          : null,
      body: Row(
        children: [
          // 1. LEFT PANE: Navigation Sidebar
          if (showSidebar) _buildSidebar(isDrawer: false),

          // 2. MIDDLE PANE: Main Content Box
          Expanded(
            flex: 5,
            child: _buildMainContent(
              showMenuButton: !showSidebar,
              showRightPanelSpacer: !showRightPanel && _currentTab == 'Dashboard',
            ),
          ),

          // 3. RIGHT PANE: Task Panel Details (Only displayed on Dashboard tab)
          if (showRightPanel && _currentTab == 'Dashboard') _buildRightPanel(),
        ],
      ),
    );
  }

  // ==========================================
  // PANE 1: SIDEBAR
  // ==========================================
  Widget _buildSidebar({bool isDrawer = false}) {
    return Container(
      width: isDrawer ? null : 250,
      color: isDrawer ? bgColor : surfaceColor.withOpacity(0.5),
      padding: const EdgeInsets.all(24),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accentBlue.withOpacity(0.4),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: const CircleAvatar(
                      radius: 22,
                      backgroundColor: Color(0xFF2962FF),
                      child: Icon(Icons.shield_outlined, color: Colors.white, size: 22),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Adith',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'Life-OS Architect',
                        style: TextStyle(color: textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: textMuted, size: 20),
                    const SizedBox(width: 8),
                    Text('Search logs...', style: TextStyle(color: textMuted, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              _sidebarItem(Icons.grid_view_rounded, 'Dashboard'),
              _sidebarItem(Icons.folder_outlined, 'Sessions'),
              _sidebarItem(Icons.playlist_add_check_rounded, 'Goals'),
              _sidebarItem(Icons.analytics_outlined, 'Analytics'),
              _sidebarItem(Icons.settings_outlined, 'Settings'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String tabName) {
    final bool isActive = _currentTab == tabName;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          setState(() {
            _currentTab = tabName;
          });
          if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
            Navigator.pop(context);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? accentBlue.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? accentBlue.withOpacity(0.3) : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon, 
                color: isActive ? const Color(0xFF2962FF) : textMuted, 
                size: 22
              ),
              const SizedBox(width: 14),
              Text(
                tabName,
                style: TextStyle(
                  color: isActive ? Colors.white : textMuted,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14.5,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // PANE 2: MAIN DASHBOARD SWITCHER
  // ==========================================
  Widget _buildMainContent({required bool showMenuButton, required bool showRightPanelSpacer}) {
    final double screenWidth = MediaQuery.of(context).size.width;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(screenWidth < 600 ? 16.0 : 32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (showMenuButton) ...[
                      IconButton(
                        icon: const Icon(Icons.menu, color: Colors.white),
                        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Text(
                      _currentTab == 'Dashboard' ? 'Deep Work Protocol' : _currentTab,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                // Indicator of overall health / status
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isSessionActive ? accentGreen.withOpacity(0.1) : Colors.white10,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: _isSessionActive ? accentGreen.withOpacity(0.3) : Colors.white.withOpacity(0.05),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _isSessionActive ? accentGreen : Colors.orangeAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isSessionActive ? 'ACTIVE CONTRACT' : 'STANDBY',
                        style: TextStyle(
                          color: _isSessionActive ? accentGreen : Colors.orangeAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Render Tab page
            Expanded(
              child: _buildTabPage(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabPage() {
    switch (_currentTab) {
      case 'Dashboard':
        return _buildDashboardTab();
      case 'Sessions':
        return _buildSessionsTab();
      case 'Goals':
        return _buildGoalsTab();
      case 'Analytics':
        return _buildAnalyticsTab();
      case 'Settings':
        return _buildSettingsTab();
      default:
        return _buildDashboardTab();
    }
  }

  // ==========================================
  // TAB 1: DASHBOARD
  // ==========================================
  Widget _buildDashboardTab() {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 600;

    final Widget innerContent = Center(
      child: SingleChildScrollView(
        child: _isSessionActive
            ? _buildActiveTimerView()
            : _buildContractForm(),
      ),
    );

    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
        child: innerContent,
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [surfaceColor, surfaceColor.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: innerContent,
    );
  }

  // Sub-Widget: The Contract Form
  Widget _buildContractForm() {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double formWidth = screenWidth < 600 ? screenWidth - 64 : 500;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: accentBlue.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: accentBlue.withOpacity(0.2), width: 1.5),
          ),
          child: Icon(
            Icons.vpn_key_outlined,
            color: accentBlue,
            size: 40,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Commit to a Focus Contract',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Declaring a goal locks this interface until you complete the timer.',
          textAlign: TextAlign.center,
          style: TextStyle(color: textMuted, fontSize: 14),
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: formWidth,
          child: TextField(
            controller: _goalController,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              labelText: 'Define your critical objective',
              labelStyle: TextStyle(color: textMuted),
              filled: true,
              fillColor: Colors.black.withOpacity(0.25),
              prefixIcon: Icon(Icons.shield_outlined, color: accentBlue, size: 20),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: accentBlue, width: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        
        // Time selection sliders & Preset chips
        const Text('SELECT COMMITMENT TIME', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
        const SizedBox(height: 16),
        SizedBox(
          width: formWidth,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _presetChip(30, '30m'),
              _presetChip(60, '60m'),
              _presetChip(120, '120m'),
              _presetChip(240, '240m'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: formWidth,
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: accentBlue,
              inactiveTrackColor: Colors.white10,
              thumbColor: Colors.white,
              overlayColor: accentBlue.withOpacity(0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              valueIndicatorTextStyle: const TextStyle(color: Colors.black),
            ),
            child: Slider(
              value: _duration.toDouble(),
              min: 15,
              max: 300,
              divisions: 19,
              label: '$_duration min',
              onChanged: (val) {
                setState(() {
                  _duration = val.toInt();
                });
              },
            ),
          ),
        ),
        const SizedBox(height: 40),

        _isLoading
            ? const CircularProgressIndicator(color: Colors.blueAccent)
            : ElevatedButton.icon(
                icon: const Icon(Icons.lock_outline_rounded, size: 18),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 50,
                    vertical: 20,
                  ),
                  backgroundColor: accentBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 10,
                  shadowColor: accentBlue.withOpacity(0.4),
                ),
                onPressed: _startSession,
                label: Text(
                  'Initiate $_duration Minute Focus Lock',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
      ],
    );
  }

  Widget _presetChip(int minutes, String label) {
    final bool isSelected = _duration == minutes;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        backgroundColor: Colors.white.withOpacity(0.03),
        selectedColor: accentBlue,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : textMuted,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        onSelected: (selected) {
          if (selected) {
            setState(() {
              _duration = minutes;
            });
          }
        },
      ),
    );
  }

  // ==========================================
  // SIDE METRICS & GOALS PANEL SUB-WIDGETS
  // ==========================================
  Widget _buildSessionMetricsCard({bool isMobile = false}) {
    return Container(
      width: isMobile ? null : 200,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SESSION METRICS',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 16),
          _metricRow('Focus Score', '$_focusScore%', accentBlue),
          const SizedBox(height: 12),
          _metricRow('Efficiency', '$_efficiency%', accentGreen),
          const SizedBox(height: 12),
          _metricRow('Resisted', '$_resistedCount', accentRed),
        ],
      ),
    );
  }

  Widget _metricRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildDailyGoalsCard({bool isMobile = false}) {
    return Container(
      width: isMobile ? null : 200,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DAILY GOALS',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 16),
          _goalRow('Focus Block', '$_completedBlocks/3', _completedBlocks >= 3),
          const SizedBox(height: 12),
          _goalRow('Code Sprint', '1/1', true),
          const SizedBox(height: 12),
          _goalRow('Research', '15m/2h', false),
        ],
      ),
    );
  }

  Widget _goalRow(String label, String progress, bool isDone) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        Row(
          children: [
            Text(
              progress,
              style: TextStyle(
                color: isDone ? accentGreen : accentRed,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              isDone ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: isDone ? accentGreen : accentRed,
              size: 13,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCentralTimerWidget(String timeStr, double percent) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 200,
              height: 200,
              child: CustomPaint(
                painter: _CircularTimerPainter(
                  percent: percent,
                  activeColor: _isIntercepted ? accentRed : accentBlue,
                  trackColor: Colors.white.withOpacity(0.05),
                ),
              ),
            ),
            Column(
              children: [
                Text(
                  _isIntercepted ? 'BLOCKED' : 'FOCUS ACTIVE',
                  style: TextStyle(
                    color: _isIntercepted ? accentRed : accentBlue,
                    fontSize: 10,
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  timeStr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Remaining',
                  style: TextStyle(color: textMuted, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // Sub-Widget: Active Timer Screen
  Widget _buildActiveTimerView() {
    final int hours = _secondsRemaining ~/ 3600;
    final int minutes = (_secondsRemaining % 3600) ~/ 60;
    final int seconds = _secondsRemaining % 60;

    final String timeStr = '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    final double percent = _secondsRemaining / (_duration * 60);

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isWide = screenWidth >= 850;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isWide)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSessionMetricsCard(),
              _buildCentralTimerWidget(timeStr, percent),
              _buildDailyGoalsCard(),
            ],
          )
        else
          Column(
            children: [
              _buildCentralTimerWidget(timeStr, percent),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: _buildSessionMetricsCard(isMobile: true)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildDailyGoalsCard(isMobile: true)),
                ],
              ),
            ],
          ),
        const SizedBox(height: 32),
        Text(
          _goalController.text,
          style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        CyberTerminal(
          logs: _activeLogs,
          streamedMessage: _aiStreamedMessage,
          isIntercepted: _isIntercepted,
        ),

        const SizedBox(height: 32),

        if (!_isIntercepted)
          OutlinedButton.icon(
            icon: const Icon(Icons.exit_to_app_rounded, size: 18),
            style: OutlinedButton.styleFrom(
              foregroundColor: accentRed,
              side: BorderSide(color: accentRed.withOpacity(0.4), width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () async {
              setState(() {
                _isIntercepted = true;
                _aiStreamedMessage = "Agent waking up...";
                _activeLogs.add("--------------------------------------------------");
                _activeLogs.add("[ALERT] Focus contract termination request intercepted!");
                _activeLogs.add("[BROKER] Deploying cognitive agent: 'gemini-2.5-flash-lite'...");
                _activeLogs.add("[BROKER] Starting motivational cognitive injection stream:");
                _activeLogs.add("--------------------------------------------------");
              });

              await _apiService.abandonSessionStream(
                _activeSessionId ?? 1,
                (word) {
                  setState(() {
                    if (_aiStreamedMessage == "Agent waking up...") {
                      _aiStreamedMessage = "";
                    }
                    _aiStreamedMessage += word;
                  });
                },
                // onSuccess: server approved the quit (200 OK)
                () {
                  setState(() {
                    _isSessionActive = false;
                    _isIntercepted = false;
                    _countdownTimer?.cancel();
                    _distractionTimer?.cancel();
                    _activeLogs.add("[SYSTEM] Quit approved by server. Session ended.");
                  });
                  _refreshAnalytics();
                },
              );
            },
            label: const Text(
              'GIVE UP',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5),
            ),
          ),

        if (_isIntercepted) ...[
          ForceStopButton(isLoading: _isForceStopping, onPressed: _forceStop),
          const SizedBox(height: 20),
          TextButton.icon(
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            onPressed: () {
              setState(() {
                _isIntercepted = false;
                _aiStreamedMessage = "";
              });
            },
            label: const Text(
              "Return to Focus Lock",
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ),
        ],
      ],
    );
  }

  // ==========================================
  // TAB 2: HISTORICAL SESSIONS
  // ==========================================
  Widget _buildSessionsTab() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Focus Records Logs', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Live session history retrieved from the PostgreSQL database.', style: TextStyle(color: textMuted, fontSize: 13)),
          const SizedBox(height: 24),
          Expanded(
            child: _isAnalyticsLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF2962FF)))
                : _analyticsData.sessionHistory.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_outlined, color: textMuted, size: 40),
                            const SizedBox(height: 12),
                            Text('No sessions recorded yet.', style: TextStyle(color: textMuted, fontSize: 14)),
                            const SizedBox(height: 4),
                            Text('Complete your first focus contract to see history here.', style: TextStyle(color: textMuted, fontSize: 12)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _analyticsData.sessionHistory.length,
                        itemBuilder: (context, index) {
                          final record = _analyticsData.sessionHistory[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      record.isCompleted ? Icons.check_circle_outline : Icons.cancel_outlined,
                                      color: record.isCompleted ? accentGreen : accentRed,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 16),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          record.goalDescription,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.5),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text(record.dateLabel, style: TextStyle(color: textMuted, fontSize: 12)),
                                            const SizedBox(width: 12),
                                            Container(width: 3, height: 3, decoration: BoxDecoration(color: textMuted, shape: BoxShape.circle)),
                                            const SizedBox(width: 12),
                                            Text('${record.durationMinutes}m', style: TextStyle(color: textMuted, fontSize: 12)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      record.status.toUpperCase(),
                                      style: TextStyle(
                                        color: record.isCompleted ? accentGreen : accentRed,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      record.scoreDeltaLabel,
                                      style: TextStyle(
                                        color: record.isCompleted ? Colors.blue[300] : Colors.red[300],
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 3: TASK TARGET GOALS
  // ==========================================
  Widget _buildGoalsTab() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Focus Checklist Objectives', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('List specific tasks to complete during your focus intervals.', style: TextStyle(color: textMuted, fontSize: 13)),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _localTaskController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Define a sub-objective task...',
                    hintStyle: TextStyle(color: textMuted),
                    filled: true,
                    fillColor: Colors.black.withOpacity(0.2),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: accentBlue),
                    ),
                  ),
                  onSubmitted: (val) async {
                    final text = val.trim();
                    if (text.isNotEmpty) {
                      _localTaskController.clear();
                      final result = await _apiService.addGoal(text);
                      if (result != null) {
                        _loadGoals();
                      } else {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Failed to add goal. Please check your network connection."),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentBlue,
                  padding: const EdgeInsets.all(18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final text = _localTaskController.text.trim();
                  if (text.isNotEmpty) {
                    _localTaskController.clear();
                    final result = await _apiService.addGoal(text);
                    if (result != null) {
                      _loadGoals();
                    } else {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Failed to add goal. Please check your network connection."),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                    }
                  }
                },
                child: const Icon(Icons.add, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _isGoalsLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF2962FF),
                    ),
                  )
                : _checklistTasks.isEmpty
                    ? Center(
                        child: Text(
                          'No checklist items yet. Define one above!',
                          style: TextStyle(color: textMuted, fontSize: 14),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _checklistTasks.length,
                        itemBuilder: (_, index) {
                          final task = _checklistTasks[index];
                          final int taskId = task['id'] as int? ?? 0;
                          final String title = task['title'] as String? ?? '';
                          final bool done = task['done'] as bool? ?? false;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withOpacity(0.04)),
                            ),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: done,
                                  activeColor: accentBlue,
                                  checkColor: Colors.white,
                                  onChanged: (val) async {
                                    if (val != null && taskId != 0) {
                                      final previousVal = task['done'];
                                      setState(() {
                                        task['done'] = val; // optimistic update
                                      });
                                      final success = await _apiService.toggleGoal(taskId, val);
                                      if (success) {
                                        _loadGoals();
                                      } else {
                                        setState(() {
                                          task['done'] = previousVal; // revert
                                        });
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text("Failed to update goal. Please check your network connection."),
                                            backgroundColor: Colors.redAccent,
                                          ),
                                        );
                                      }
                                    }
                                  },
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    title,
                                    style: TextStyle(
                                      color: done ? textMuted : Colors.white,
                                      fontSize: 14.5,
                                      decoration: done ? TextDecoration.lineThrough : null,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey, size: 20),
                                  onPressed: () async {
                                    if (taskId != 0) {
                                      final removedTask = _checklistTasks[index];
                                      setState(() {
                                        _checklistTasks.removeAt(index); // optimistic update
                                      });
                                      final success = await _apiService.deleteGoal(taskId);
                                      if (success) {
                                        _loadGoals();
                                      } else {
                                        setState(() {
                                          _checklistTasks.insert(index, removedTask); // revert
                                        });
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text("Failed to delete goal. Please check your network connection."),
                                            backgroundColor: Colors.redAccent,
                                          ),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 4: CANVAS ANALYTICS
  // ==========================================
  Widget _buildAnalyticsTab() {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isNarrow = screenWidth < 750;

    final Widget disciplineChartCard = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Discipline Coefficients',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              if (_isAnalyticsLoading)
                const SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Color(0xFF2962FF),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Live score trend — last 7 days from database', style: TextStyle(color: textMuted, fontSize: 11)),
          const SizedBox(height: 24),
          Expanded(
            child: DisciplineLineChart(
              dataPoints: _analyticsData.graphPoints,
            ),
          ),
        ],
      ),
    );

    final Widget cognitiveResistsCard = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cognitive Resists',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
          ),
          const SizedBox(height: 6),
          Text('Quitting pushbacks handled successfully', style: TextStyle(color: textMuted, fontSize: 11)),
          const SizedBox(height: 24),
          const Expanded(
            child: CustomBarChart(
              dataPoints: [3, 1, 4, 2, 5, 3, 2],
              labels: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: EdgeInsets.all(screenWidth < 600 ? 16 : 28),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Focus & Discipline Metrics', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('A review of historical metrics retrieved by local databases.', style: TextStyle(color: textMuted, fontSize: 13)),
          const SizedBox(height: 24),
          Expanded(
            child: isNarrow
                ? SingleChildScrollView(
                    child: Column(
                      children: [
                        SizedBox(height: 260, child: disciplineChartCard),
                        const SizedBox(height: 20),
                        SizedBox(height: 260, child: cognitiveResistsCard),
                      ],
                    ),
                  )
                : Row(
                    children: [
                      Expanded(child: disciplineChartCard),
                      const SizedBox(width: 24),
                      Expanded(child: cognitiveResistsCard),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 5: SYSTEM SETTINGS
  // ==========================================
  Widget _buildSettingsTab() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Broker Protocol Settings', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Configure kernel endpoints and developer flags.', style: TextStyle(color: textMuted, fontSize: 13)),
          const SizedBox(height: 32),
          Expanded(
            child: ListView(
              children: [
                _settingToggleTile(
                  icon: Icons.notifications_active_outlined,
                  title: 'Strict Agent Injections',
                  subtitle: 'Stream aggressive motivational notifications during focus sessions.',
                  val: true,
                ),
                _settingToggleTile(
                  icon: Icons.shield_outlined,
                  title: 'Eye Tracker Supervision',
                  subtitle: 'Enable browser window and visual validation to check focus stability.',
                  val: false,
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white10),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      const Icon(Icons.dns_outlined, color: Colors.blueAccent, size: 24),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Backend kernel Server URL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.5)),
                            const SizedBox(height: 4),
                            Text('FastAPI server running in workspace context', style: TextStyle(color: Colors.grey, fontSize: 12.5)),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: TextField(
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          controller: TextEditingController(text: ApiService.baseUrl),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.black.withOpacity(0.2),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Colors.white10),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: accentBlue),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingToggleTile({required IconData icon, required String title, required String subtitle, required bool val}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.blueAccent, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.5)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: textMuted, fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: val,
            activeColor: accentBlue,
            onChanged: (changedVal) {},
          ),
        ],
      ),
    );
  }

  // ==========================================
  // PANE 3: RIGHT PANEL (Dashboard Details)
  // ==========================================
  Widget _buildRightPanel() {
    return Container(
      width: 320,
      color: surfaceColor.withOpacity(0.3),
      padding: const EdgeInsets.all(24),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Focus Operations',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 24),

              // Discipline points summary box
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accentBlue.withOpacity(0.15), Colors.transparent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accentBlue.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Discipline Score',
                          style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        ),
                        Icon(Icons.stars_rounded, color: Colors.blue[300], size: 18),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _isAnalyticsLoading
                        ? const SizedBox(
                            height: 38,
                            child: Center(
                              child: SizedBox(
                                width: 22, height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF2962FF),
                                ),
                              ),
                            ),
                          )
                        : Text(
                            '${_analyticsData.disciplineScore}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          _analyticsData.disciplineScore >= 0
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          color: const Color(0xFF00E676),
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_analyticsData.disciplineScore} pts total',
                          style: const TextStyle(color: Color(0xFF00E676), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Text('from real sessions', style: TextStyle(color: textMuted, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              const Text('Active Operations', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              const SizedBox(height: 16),

              _activeOperationTile(
                icon: Icons.code,
                title: 'Refactor Rust async executor',
                subtitle: 'Active Project Focus Block',
              ),
              _activeOperationTile(
                icon: Icons.storage_rounded,
                title: 'Precompute vector embeddings',
                subtitle: 'DB Optimization Tasks',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _activeOperationTile({required IconData icon, required String title, required String subtitle}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.blueAccent, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title, 
                  maxLines: 1, 
                  overflow: TextOverflow.ellipsis, 
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: textMuted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// GLOWING NEON CIRCULAR PAINTER CANVAS
// ==========================================
class _CircularTimerPainter extends CustomPainter {
  final double percent;
  final Color activeColor;
  final Color trackColor;

  _CircularTimerPainter({
    required this.percent,
    required this.activeColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.width / 2;
    final Offset center = Offset(radius, radius);
    final double strokeWidth = 12.0;

    // 1. Draw solid backdrop path
    final Paint trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius - strokeWidth, trackPaint);

    // 2. Draw outer blur shadow glow
    final Paint glowPaint = Paint()
      ..color = activeColor.withOpacity(0.18)
      ..strokeWidth = strokeWidth + 6.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Start angle at -pi/2 (which is vertical 12 o'clock)
    final double sweepAngle = 2 * 3.14159 * percent;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth),
      -3.14159 / 2,
      sweepAngle,
      false,
      glowPaint,
    );

    // 3. Draw active neon foreground stroke
    final Paint activePaint = Paint()
      ..color = activeColor
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth),
      -3.14159 / 2,
      sweepAngle,
      false,
      activePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
