/// Default copy currently rendered by booking-website/organisation-home.
/// Display it in the editor without marking unchanged settings as unsaved.
const defaultWebsiteHeroHeading = 'A space for your next great moment.';
String defaultWebsiteDescription(String title) =>
    'Discover the spaces and services at $title. Find your time and book directly with us.';
String defaultWebsiteBusinessDescription(
  String type,
  String name,
) => switch (type) {
  'turf' =>
    'Make time for your next game. Choose your turf, sport and a time that works for your team.',
  'pool' =>
    'A little movement. A little time for yourself. Reserve your next swim.',
  'badminton' =>
    'Bring your doubles partner or practise your singles. Your next rally starts here.',
  'tennis' =>
    'Find your rhythm on court. Choose an available time for your next match.',
  'basketball' => 'Get your team together and make the court yours for a game.',
  'hall' =>
    'Find a space for your next occasion. Explore available dates and venue tariffs.',
  _ => 'Explore $name and find your next available booking.',
};
