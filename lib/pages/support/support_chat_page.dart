import 'package:flutter/material.dart';

import '../../services/support/support_agent_service.dart';

/// v1.3.3-T4 — in-app support chat.
///
/// Non-tech-first rules apply here harder than anywhere else:
///   * no jargon (never "scraper", "source probe", "RPC")
///   * the first user message decides the language — we never ask
///   * a weak answer offers ONE obvious action ("Send to a person")
///   * the whole screen works offline (tier 1 FAQ)
class SupportChatPage extends StatefulWidget {
  const SupportChatPage({super.key, this.initialTopic = 'other'});

  final String initialTopic;

  static Route<void> route({String topic = 'other'}) => MaterialPageRoute<void>(
        builder: (_) => SupportChatPage(initialTopic: topic),
      );

  @override
  State<SupportChatPage> createState() => _SupportChatPageState();
}

class _SupportChatPageState extends State<SupportChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  bool _busy = false;
  bool _ticketSent = false;
  String _lang = 'en';

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _hinglish => _lang == 'hi';

  String _t(String en, String hi) => _hinglish ? hi : en;

  @override
  void initState() {
    super.initState();
    _msgs.add(_Msg(
      text: _t(
        'Hi! Tell me what is not working and I will help. ✨',
        'Namaste! Batao kya kaam nahi kar raha, main help karta hoon. ✨',
      ),
      fromUser: false,
    ));
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    setState(() {
      _msgs.add(_Msg(text: text, fromUser: true));
      _busy = true;
    });
    _scrollDown();

    // The user's first words decide the language for the whole session.
    if (_msgs.where((m) => m.fromUser).length == 1) {
      _lang = SupportAgentService.detectLanguage(text);
    }

    final answer = await SupportAgentService.ask(text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (answer.hasText) {
        _msgs.add(_Msg(text: answer.text, fromUser: false));
      } else {
        _msgs.add(_Msg(
          text: _t(
            'I am not sure about this one. Want me to send it to a person?',
            'Is baare me mujhe pakka nahi pata. Kya main kisi insaan ko bhej doon?',
          ),
          fromUser: false,
          offerTicket: true,
        ));
      }
    });
    _scrollDown();
  }

  Future<void> _sendToHuman() async {
    if (_ticketSent) return;
    setState(() => _busy = true);
    final id = await SupportAgentService.openTicket(topic: widget.initialTopic);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ticketSent = true;
      _msgs.add(_Msg(
        text: id == null
            ? _t(
                'Could not reach us right now. Please try again in a little while. 🙏',
                'Abhi hum tak nahi pahunch paya. Thodi der baad phir try karo. 🙏',
              )
            : _t(
                'Sent! A person will look at it soon. Thanks for the details. 🙏',
                'Bhej diya! Koi insaan jaldi dekh lega. Details ke liye shukriya. 🙏',
              ),
        fromUser: false,
      ));
    });
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('Help', 'Madad')),
        leading: BackButton(onPressed: () => Navigator.of(context).maybePop()),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                itemCount: _msgs.length,
                itemBuilder: (_, i) => _bubble(theme, _msgs[i]),
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            _composer(theme),
          ],
        ),
      ),
    );
  }

  Widget _bubble(ThemeData theme, _Msg m) {
    final mine = m.fromUser;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine
              ? theme.colorScheme.primary.withValues(alpha: 0.16)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.text, style: theme.textTheme.bodyMedium),
            if (m.offerTicket && !_ticketSent)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.tonal(
                  onPressed: _busy ? null : _sendToHuman,
                  child: Text(_t('Send to a person', 'Kisi insaan ko bhejo')),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _composer(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: _t('Type your problem…', 'Apni problem likho…'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _busy ? null : () => _send(),
            icon: const Icon(Icons.send_rounded),
            tooltip: _t('Send', 'Bhejo'),
          ),
        ],
      ),
    );
  }
}

class _Msg {
  _Msg({required this.text, required this.fromUser, this.offerTicket = false});
  final String text;
  final bool fromUser;
  final bool offerTicket;
}