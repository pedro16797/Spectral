# Agent Guidance for Spectral

Welcome, Agent. This document serves as the primary entry point for understanding the goals, technical standards, and safety protocols for Spectral.

## Project Overview
Spectral is a mobile-first application (Android priority, with iOS compatibility in mind) for observing spectral and wave data (audio, RF, etc.) in a modern, elegant, and performant way.

## Main Objectives
We are currently in the initial setup phase. Our focus is:
1.  **Project Foundation:** Establishing a solid directory structure and documentation.
2.  **Architecture Planning:** Defining a cross-platform-ready architecture that ensures high performance for real-time visualizations.
3.  **MVP Definition:** Planning for core features:
    - Real-time wave visualization.
    - FFT bar chart.
    - Waterfall display.
    - Highly configurable themes and modes.

## Core Directives
To maintain the quality and performance of this visualization tool:
-   **Performance First:** Spectral data processing and rendering must be highly optimized.
-   **Cross-Platform Readiness:** While Android is the first target, avoid platform-specific lock-in where possible.
-   **Localization:** Account for internationalization from the start. All strings should be externalized.
-   **Minimize Blast Radius:** Touch only the files and functions required for your specific task.
-   **Verify Everything:** Use `list_files`, `read_file`, and relevant verification tools to confirm every modification.

## Working Workflow
1.  **Plan:** Propose a detailed plan before making changes.
2.  **Isolate:** Work on the minimum subset of code needed.
3.  **Validate:** Run tests and use frontend verification tools where applicable.
4.  **Visualize:** Assess if the change has a visual impact. If so, it is **imperative** to update the project's screenshots using `scripts/generate_screenshots.py`.
5.  **Review:** Perform a self-review or request a review on your diff before finalizing.

## Documentation Maintenance
Keep the project documentation accurate:
-   **`README.md`**: Update with high-level project status and setup instructions.
-   **`AGENTS.md`**: (This file) Update with major goals and guidelines.
-   **`docs/project_structure.md`**: Update whenever directories or major files are added or moved.
-   **`docs/roadmap.md`**: Update as features are implemented or prioritized.

## Localization
-   **Base Language:** English (`en`).
-   **Storage:** JSON files in `resources/locales/`.
