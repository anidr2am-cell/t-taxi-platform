import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../widgets/analytics_consent_banner.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../data/privacy_policy_content.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({
    super.key,
    this.markdownLoader = PrivacyPolicyContent.load,
    this.initialMarkdown,
  });

  final Future<String> Function() markdownLoader;
  final String? initialMarkdown;

  @visibleForTesting
  static MarkdownStyleSheet styleSheet(BuildContext context) {
    final theme = Theme.of(context);
    return MarkdownStyleSheet(
      h1: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
      h2: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
      h3: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
      p: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
      listBullet: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
      blockquote: theme.textTheme.bodyMedium?.copyWith(
        height: 1.5,
        color: AppTokens.textSecondary,
      ),
      blockquoteDecoration: BoxDecoration(
        color: AppTokens.surface,
        border: Border(
          left: BorderSide(color: AppTokens.primary, width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      tableHead: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      tableBody: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
      tableBorder: TableBorder.all(color: AppTokens.border),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 8,
      ),
      strong: const TextStyle(fontWeight: FontWeight.w700),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppTokens.border)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final width = MediaQuery.sizeOf(context).width;
    final maxWidth = width >= 900 ? 920.0 : double.infinity;

    return Scaffold(
      backgroundColor: AppTokens.background,
      appBar: AppBar(title: Text(l10n.t('privacy_policy_title'))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: initialMarkdown != null
                ? _PrivacyPolicyBody(markdown: initialMarkdown!)
                : FutureBuilder<String>(
                    future: markdownLoader(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError || snapshot.data == null) {
                        return Center(
                          child: Padding(
                            padding: AppUi.pagePadding(context),
                            child: Text(l10n.t('privacy_policy_load_failed')),
                          ),
                        );
                      }
                      return _PrivacyPolicyBody(markdown: snapshot.data!);
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _PrivacyPolicyBody extends StatelessWidget {
  const _PrivacyPolicyBody({required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      child: ListView(
        padding: AppUi.pagePadding(context),
        children: [
          MarkdownBody(
            data: markdown,
            selectable: true,
            styleSheet: PrivacyPolicyPage.styleSheet(context),
            extensionSet: md.ExtensionSet.gitHubFlavored,
          ),
          const SizedBox(height: AppTokens.spaceMd),
          const AnalyticsConsentSettingsButton(),
        ],
      ),
    );
  }
}
