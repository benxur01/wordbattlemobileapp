# Project Context: Word Battle 8-Week Daily Development Roadmap (Nov 10 – Dec 31, 2026)

Always reference and follow the daily roadmap defined in `ROADMAP.md` located at the root of the repository.
Whenever the user returns and asks "Bugungi ishni qilaylik" or asks what's next:
1. Check current date and determine which day of the 8-week sprint we are on.
2. Confirm the planned feature/task for the day.
3. Break the day's feature down into multiple logical, atomic steps (e.g., 3-5 commits: UI components, logic/state management, tests, integration & polish).
4. Make multiple granular conventional commits (not just a single commit) throughout the work.
5. Push the commits to GitHub `origin/main`.
6. When day's work is completed, explicitly tell the user "Bugungi ish tugadi" and list every commit pushed.
7. Keep code synced between `wordbattlemobileapp-git` and `wordbattlemobileapp-main`.

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
