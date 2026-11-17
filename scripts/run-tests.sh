#!/usr/bin/env bash
# Unit tests + coverage (the coverage report is consumed by SonarQube).
set -euo pipefail
mkdir -p reports
pytest --junitxml=reports/junit.xml \
       --cov --cov-report=xml:reports/coverage.xml --cov-report=term-missing \
       --cov-fail-under=80
