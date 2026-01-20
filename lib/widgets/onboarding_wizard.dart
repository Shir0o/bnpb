import 'package:flutter/material.dart';

/// Follow-up destinations the onboarding wizard can deep link to once the
/// user chooses an action.
enum OnboardingFollowUp {
  /// Navigate to contact import tools on the home tab.
  importContacts,

  /// Navigate to the add-contact experience so tags can be curated early.
  manageTags,

  /// Navigate to notification settings for fine tuning reminders.
  notificationSettings,
}

/// Result returned from the onboarding wizard dialog.
class OnboardingResult {
  const OnboardingResult({
    required this.completed,
    this.followUp,
  });

  /// Whether the user completed (or skipped) the onboarding flow.
  final bool completed;

  /// Optional follow-up action requested from the final step.
  final OnboardingFollowUp? followUp;
}

/// Full screen dialog that walks first time users through the primary setup
/// tasks required by the app.
class OnboardingWizard extends StatefulWidget {
  const OnboardingWizard({super.key});

  @override
  State<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends State<OnboardingWizard> {
  late final PageController _controller;
  int _index = 0;

  static const List<_OnboardingStep> _steps = [
    _OnboardingStep(
      icon: Icons.download_done_outlined,
      title: 'Import your people',
      description:
          'Restore an existing backup or spreadsheet to seed the timeline '
          'and prayer lists right away. Use the restore icon on the Contacts '
          'tab at any time to bring additional records in.',
      actionLabel: 'Import contacts',
      followUp: OnboardingFollowUp.importContacts,
    ),
    _OnboardingStep(
      icon: Icons.sell_outlined,
      title: 'Create meaningful tags',
      description:
          'Group people by ministry focus, campus, or teams. When adding or '
          'editing a contact you can create new tags and reuse them to keep '
          'lists organised from the start.',
      actionLabel: 'Review tag options',
      followUp: OnboardingFollowUp.manageTags,
    ),
    _OnboardingStep(
      icon: Icons.notifications_active_outlined,
      title: 'Stay on top of follow-ups',
      description:
          'Tune prayer nudges, follow-up reminders, and the new weekly & '
          'monthly reviews so the app highlights outstanding requests and '
          'stale relationships before they slip through.',
      actionLabel: 'Configure notifications',
      followUp: OnboardingFollowUp.notificationSettings,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goNext() {
    if (_index >= _steps.length - 1) {
      Navigator.of(context).pop(const OnboardingResult(completed: true));
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  void _jumpToFollowUp(_OnboardingStep step) {
    Navigator.of(context).pop(
      OnboardingResult(
        completed: true,
        followUp: step.followUp,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context)
                        .pop(const OnboardingResult(completed: true));
                  },
                  child: const Text('Skip'),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _steps.length,
                  physics: const ClampingScrollPhysics(),
                  onPageChanged: (value) {
                    setState(() {
                      _index = value;
                    });
                  },
                  itemBuilder: (context, index) {
                    final step = _steps[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 8,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            step.icon,
                            size: 72,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            step.title,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            step.description,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 32),
                          FilledButton.icon(
                            onPressed: () => _jumpToFollowUp(step),
                            icon: Icon(step.icon),
                            label: Text(step.actionLabel),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _steps.length,
                        (i) => Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _index
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _goNext,
                        child: Text(
                          _index >= _steps.length - 1 ? 'Get started' : 'Next',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingStep {
  const _OnboardingStep({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.followUp,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final OnboardingFollowUp followUp;
}
