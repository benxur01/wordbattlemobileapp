# Project Context: Word Battle 8-Week Daily Development Roadmap (Nov 10 – Dec 31, 2026)

Always reference and follow the daily roadmap defined in `ROADMAP.md` located at the root of the repository.
Whenever the user returns and asks "Bugungi ishni qilaylik", "Bugun <sana> nima qilishimiz kerak?", or asks what's next:
1. Check current date and determine which day of the 8-week sprint we are on.
2. Confirm the planned feature/task for the day.
3. Break the day's feature down into as many clean, logical, atomic commits as possible (**target 8–12+ genuine atomic commits per day**, never bundling everything into 1–2 commits):
   - Backend API / service changes in separate commits
   - Backend unit & integration tests in separate commits
   - Frontend models / DTOs / API client methods in separate commits
   - Pure logic / validators / utilities in separate commits
   - Dedicated reusable UI widgets in separate commits
   - Animation, light/dark theme adaptation, and accessibility (`a11y`) polish in separate commits
   - Screen integration & `app_root.dart` wiring in separate commits
   - Unit tests, widget tests (including edge cases), and layout/stress tests in separate commits
4. Make each atomic conventional commit (`feat`, `refactor`, `style`, `a11y`, `test`) incrementally as each logical unit is verified, with zero empty/fake commits.
5. Push all commits to GitHub `origin/main` cleanly.
6. When day's work is completed, explicitly tell the user "Bugungi ish tugadi" and list every commit pushed (with commit hashes and descriptions).
7. Always keep code synced between `wordbattlemobileapp-git` and `wordbattlemobileapp-main`.

## 💎 Pro UI/UX Engineering & Delight Standards (Apple Design Award Benchmark)
For every UI component, screen, interaction, or animation implemented across all sprints:
1. **Micro-interactions & Physics-based Motion**:
   - Every interactive element (buttons, cards, chips) must use spring curves (`Curves.easeOutBack`, `Curves.easeInOutCubic`) and scale-down press feedback (e.g., shrinking to `0.96` on touch and popping back).
   - Animated count-up rolls (`AnimatedCounter`) for scores, coins, ratings, and streak counters.
   - Dynamic error feedback: subtle spring shake (`ErrorShakeAnimation`) with tactile haptic buzz when an invalid word is submitted instead of flat error text.
2. **Sensory Synergy (Sound + Haptics)**:
   - Harmonize visual changes with tailored tactile feedback (`HapticFeedback.lightImpact()`, `selectionClick()`, `mediumImpact()`) and synchronized audio cues (`SoundEffects`).
3. **Glassmorphism, Depth & Specular Lighting**:
   - Authentic liquid frosted glass (`BackdropFilter(sigmaX: 20-30, sigmaY: 20-30)`) with subtle top-edge specular borders (`Border(top: BorderSide(color: Colors.white.withOpacity(0.15)))`) and multi-layer elevation.
4. **Delightful Loading & Joyful Empty States**:
   - Synchronized shimmer skeletons (`ShimmerScope`) for all loading lists, cards, and avatars to eliminate jarring layout pops.
   - Illustrated or animated empty states with subtle idle floating/breathing animations.
   - High-energy celebration effects (GPU-accelerated confetti burst, gold particle sweeps, festive snow physics).
5. **Ergonomic Thumb-Zone & Typographic Rhythm**:
   - Mobile-first thumb reachability, smooth swipe/drag dismissals for modal sheets, and pixel-perfect typographic hierarchy (Space Grotesk + JetBrains Mono) with tabular numbers for timers and counters.
