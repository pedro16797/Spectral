# Contributing to Spectral

Thank you for your interest in contributing to Spectral! We aim for high-performance, elegant, and user-friendly spectral visualization.

---

## Core Principles

### Predictable, Low-Risk Contributions
We value stability and performance. Changes should be tightly scoped and well-tested to ensure they don't break the real-time visualization engine or the user interface.

### Solve One Problem at a Time
- Keep each PR focused on a single bug or feature.
- Avoid mixing refactors or formatting changes with behavior changes.

### Minimize Blast Radius
- Touch only the files and functions required for the task.
- Avoid "drive-by improvements" in unrelated code.

### Prove the Change
- Add or run targeted tests for the affected path.
- Verify UI changes across different screen sizes and orientations if applicable.

---

## Visual Documentation

Maintaining up-to-date visual documentation is critical for Spectral. When introducing new features or modifying the UI, it is **imperative** to evaluate whether new screenshots are needed or if existing ones must be updated.

### Generating Screenshots
We use an automated script to capture consistent screenshots of the app. This requires [Playwright](https://playwright.dev/python/).

1.  **Build the Web App:**
    ```bash
    flutter build web --profile
    ```
2.  **Run the Screenshot Script:**
    ```bash
    python3 scripts/generate_screenshots.py
    ```
    Generated images are saved to `resources/screenshots/`.

Contributors are expected to include updated screenshots in their PRs if their changes impact the visual state of the application.

---

## AI-Assisted Workflow

If you are using an AI agent to contribute, please follow these guidelines:
1.  **Propose a Plan:** Always start with a detailed proposal and plan.
2.  **Minimum Changes:** Make only the minimum required changes.
3.  **Preserve Interfaces:** Do not change existing APIs or data structures unless necessary.
4.  **Verify:** Use available tools to confirm every modification.

---

## PR Process
1.  **Self-Review:** Review your own diff to ensure it follows these guidelines.
2.  **Description:** Use a clear summary and explain the "why" behind the change.
3.  **Validation:** List the checks and tests performed.

Thanks for helping build Spectral!
