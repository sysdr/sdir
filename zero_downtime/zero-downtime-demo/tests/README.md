# UI Testing for Zero-Downtime Dashboard

This directory contains comprehensive UI tests for the Zero-Downtime Deployment Dashboard using Playwright.

## 🚀 Quick Start

### Prerequisites
1. Ensure the dashboard is running: `./run_demo.sh start`
2. Install dependencies: `npm install`
3. Install Playwright browsers: `npx playwright install`

### Run Tests

#### Using the test runner script (Recommended)
```bash
# Run all UI tests
./scripts/run_ui_tests.sh

# Run only UI tests
./scripts/run_ui_tests.sh ui

# Run tests in headed mode (visible browser)
./scripts/run_ui_tests.sh headed

# Run tests in debug mode
./scripts/run_ui_tests.sh debug
```

#### Using npm scripts
```bash
# Run all tests
npm test

# Run UI tests only
npm run test:ui

# Run tests in headed mode
npm run test:headed

# Run tests in debug mode
npm run test:debug

# View HTML report
npm run test:report
```

## 📋 Test Coverage

The test suite covers:

### ✅ UI Elements
- Dashboard title and main sections
- Deployment strategy sections (Rolling, Blue-Green, Canary)
- Status indicators and information
- Control buttons and interactive elements

### ✅ Button Interactions
- Start/Stop button functionality
- Button click responses
- Status updates after button clicks
- Error handling for non-existent elements

### ✅ User Experience
- Page refresh behavior
- Real-time updates
- Responsive design (mobile, tablet, desktop)
- Error state handling

### ✅ Cross-Browser Testing
- Chrome (Chromium)
- Firefox
- Safari (WebKit)
- Mobile Chrome
- Mobile Safari

## 🔧 Configuration

### Playwright Config (`playwright.config.js`)
- **Base URL**: `http://localhost:3000`
- **Test Directory**: `./tests`
- **Parallel Execution**: Enabled
- **Retries**: 2 on CI, 0 locally
- **Screenshots**: On failure
- **Videos**: Retained on failure
- **Traces**: On first retry

### Test Structure
```
tests/
├── dashboard-ui.spec.js    # Main UI test suite
└── README.md              # This file

scripts/
└── run_ui_tests.sh        # Test runner script
```

## 📊 Test Reports

After running tests, you can view:

### HTML Report
```bash
npm run test:report
```
Opens an interactive HTML report with:
- Test results summary
- Screenshots on failure
- Video recordings
- Console logs
- Network traces

### JSON Report
Located at: `test-results/results.json`
Contains structured test results for CI/CD integration.

### JUnit Report
Located at: `test-results/results.xml`
Compatible with CI/CD systems like Jenkins, GitLab CI, etc.

## 🐛 Debugging

### Debug Mode
```bash
npm run test:debug
```
Opens Playwright Inspector for step-by-step debugging.

### Headed Mode
```bash
npm run test:headed
```
Runs tests with visible browser windows.

### Specific Test
```bash
npx playwright test dashboard-ui.spec.js --grep "should display main dashboard elements"
```

## 🔄 CI/CD Integration

### GitHub Actions Example
```yaml
name: UI Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '18'
      - run: npm ci
      - run: npx playwright install --with-deps
      - run: ./run_demo.sh start
      - run: npm test
      - uses: actions/upload-artifact@v3
        if: always()
        with:
          name: playwright-report
          path: playwright-report/
```

## 🛠️ Customization

### Adding New Tests
1. Create a new test file in `tests/`
2. Follow the existing test structure
3. Use descriptive test names
4. Add appropriate assertions

### Modifying Selectors
If your dashboard HTML structure changes, update the selectors in `dashboard-ui.spec.js`:
- Use `data-testid` attributes for stable selectors
- Prefer semantic selectors over CSS classes
- Test multiple selector strategies for robustness

### Environment Variables
Set these for different environments:
- `PLAYWRIGHT_BASE_URL`: Override base URL
- `PLAYWRIGHT_HEADLESS`: Set to `false` for headed mode
- `PLAYWRIGHT_BROWSERS`: Specify browsers to test

## 📝 Best Practices

1. **Test Isolation**: Each test should be independent
2. **Descriptive Names**: Use clear, descriptive test names
3. **Wait Strategies**: Use proper wait conditions, not arbitrary timeouts
4. **Error Handling**: Test both success and failure scenarios
5. **Accessibility**: Include accessibility testing where possible
6. **Performance**: Monitor test execution time

## 🆘 Troubleshooting

### Common Issues

**Dashboard not accessible**
```bash
# Check if dashboard is running
curl http://localhost:3000

# Restart dashboard
./run_demo.sh restart
```

**Playwright browsers not installed**
```bash
npx playwright install
```

**Tests failing on CI**
- Ensure all dependencies are installed
- Check browser installation
- Verify dashboard is accessible
- Review CI logs for specific errors

**Slow test execution**
- Use `--workers=1` for debugging
- Check network connectivity
- Review wait conditions

## 📚 Resources

- [Playwright Documentation](https://playwright.dev/)
- [Playwright Test API](https://playwright.dev/docs/api/class-test)
- [Best Practices](https://playwright.dev/docs/best-practices)
- [Debugging Guide](https://playwright.dev/docs/debug) 