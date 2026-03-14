# Project Structure

This document outlines the directory structure and the purpose of each component in the Spectral repository.

## Directory Overview

- **`src/`**: Contains the core application logic and source code.
    - **`audio/`**: Components for audio capturing and processing.
    - **`rf/`**: Components for RF data acquisition and processing (Future).
    - **`core/`**: Shared signal processing logic (FFT, windowing, filters).
    - **`ui/`**: User interface components and visualization rendering logic.
    - **`services/`**: Background services, data providers, and system integrations.
    - **`utils/`**: General helper functions and shared utilities.
- **`docs/`**: Project documentation, including roadmaps, architecture guides, and sprint plans.
- **`config/`**: Configuration files and default settings for the application.
- **`resources/`**: Static assets.
    - **`locales/`**: JSON files for internationalization.
    - **`themes/`**: Theme definitions and style constants.
- **`tests/`**: Unit, integration, and end-to-end tests.

## Root Files

- **`AGENTS.md`**: Guidance and roadmap for AI agents working on the project.
- **`CONTRIBUTING.md`**: Guidelines for contributing to the project.
- **`README.md`**: General project overview and setup instructions.
- **`LICENSE`**: The project's MIT license terms.
