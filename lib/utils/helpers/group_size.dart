/// Shared wording for configurable pool offers and booking summaries.
String groupSizeLabel(String mode, Object people) => switch (mode) {
  'exact' => 'Exactly $people people',
  'up_to' => 'Up to $people people',
  'at_least' => '$people+ people',
  _ => 'Group size unavailable',
};

String groupSizeExplanation(String mode, Object people) => switch (mode) {
  'exact' => 'Only a group of $people people qualifies.',
  'up_to' => 'Groups of 1 to $people people qualify.',
  'at_least' =>
    'Groups of $people or more qualify, subject to available pool capacity.',
  _ => 'Choose a group size rule.',
};
