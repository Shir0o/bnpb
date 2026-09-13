# Infer recurring log patterns deterministically on-device

Recurring log patterns are inferred from a Contact's local Interaction history using deterministic matching and cadence rules; the LLM is used only to parse a free-form scripture reference from the latest Interaction note. We chose this over sending history to the LLM because cadence and sequence inference are math-like, and because BNPB's privacy promise allows only the active note or Interaction to reach the model. The trade-off is less robust grouping of semantically similar activity names (for example, "Bible reading" and "Bible study" remain separate patterns), which is accepted for the first release and can be revisited through deterministic aliases.

- Status: accepted
