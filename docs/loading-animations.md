# Shared loading animations

All request-loading motion is implemented in `lib/design_system/animations/app_loading_animation.dart` and exported through `design_system.dart`. Feature screens continue using their existing models and Cubits; animations never access repositories, storage or network clients.

- `AppLoadingState(initial: true, label: ...)`: orbit animation with “Getting things ready” and a contextual loading caption. Used for startup and initial data loads.
- `AppLoadingState(initial: false)` / `AppRefreshIndicator`: pulsing status dot beside “Refreshing…”. Rendered inline while existing content stays in place. Availability and location reads use contextual labels.
- `AppSavingDots`: decorative staggered dots inside shared `AppButton` busy states. `busyLabel` optionally provides a contextual action label, such as “Saving booking…”.
- `AppSavingIndicator`: the same saving motion with an accessible label for operations outside a button, such as bank-setting changes.

The approved orbit has a 900ms inner cycle and 1440ms reverse outer cycle, combined into a seamless 7200ms controller loop. The refresh pulse uses 1530ms; saving dots use 720ms with staggered phases. Colors come from the current theme; no new packages or image assets are required.

Animation controllers stop when `TickerMode` disables an inactive tab and dispose with their widgets. When the system requests reduced motion, all indicators remain visible but static. Spoken loading labels are stable live regions, with decorative paint excluded from semantics. Each animated region has its own repaint boundary.

Loaded bookings, accounts, Home sections, bank settings and team data stay visible while their existing Cubit refresh flags are active. Existing empty Home sections also remain visible during refresh. A previously loaded availability grid stays visible but disabled while checking; changing the date/space still clears incompatible slots through the existing Cubit. Loading animations introduce no artificial delays or new requests. Busy buttons remain disabled to prevent duplicate actions.

The determinate setup-step bars in court/pool configuration and the income comparison bars in Accounts remain unchanged: they represent actual steps or financial values, not buffering.

Tests cover reduced motion, semantics, inactive-tab lifecycle, duplicate-tap prevention, narrow layouts with enlarged text, distinct animation frames and visible cached cards during refresh. Local light/dark screenshots are generated under `.local/animation-previews/` for visual review.

Build only was requested. Preparing the Android APK does not install it, restart the phone app or change Supabase data.
