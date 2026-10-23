import { createRequire } from 'node:module'
import { mkdirSync, readFileSync, statSync } from 'node:fs'
import { homedir } from 'node:os'
import { join, resolve, sep } from 'node:path'

const url = process.env.CAPTURE_URL
const captureDir = process.env.CAPTURE_DIR
if (!url || !captureDir) {
  console.error('Set CAPTURE_URL and CAPTURE_DIR.')
  process.exit(1)
}

const projectDir = resolve(process.env.PROJECT_DIR || process.cwd())
const outputDir = resolve(captureDir)
if (outputDir === projectDir || outputDir.startsWith(projectDir + sep)) {
  console.error('CAPTURE_DIR must stay outside the project source tree.')
  process.exit(1)
}

const playwrightRoot = join(homedir(), '.local/share/omgithub-playwright')
const require = createRequire(join(playwrightRoot, 'package.json'))
const { chromium } = require('playwright')
const config = JSON.parse(readFileSync(join(playwrightRoot, 'linux.json'), 'utf8'))

if (process.platform === 'linux' && !process.env.DISPLAY) {
  process.env.DISPLAY = ':' + readFileSync(join(playwrightRoot, 'display'), 'utf8').trim()
}

mkdirSync(outputDir, { recursive: true })

const failure = (message, exitCode, cause) =>
  Object.assign(new Error(message, { cause }), { exitCode })
const temporary = (message, cause) => failure(message, 75, cause)

let browser
let exitCode = 0

try {
  try {
    browser = await chromium.launch({ ...config.browser.launchOptions, timeout: 30000 })
  } catch (error) {
    throw temporary(`Could not launch browser: ${error.message}`, error)
  }

  for (const [name, width, height] of [
    ['desktop', 1440, 900],
    ['mobile', 390, 844],
  ]) {
    let page
    try {
      try {
        page = await browser.newPage({ viewport: { width, height } })
      } catch (error) {
        throw temporary(`Could not open ${name} page: ${error.message}`, error)
      }

      page.setDefaultTimeout(30000)
      page.on('pageerror', (error) => console.error(`[${name}] pageerror: ${error.message}`))

      let response
      try {
        response = await page.goto(url, { waitUntil: 'load', timeout: 45000 })
      } catch (error) {
        throw temporary(`Could not navigate to ${url}: ${error.message}`, error)
      }

      if (!response) {
        throw temporary(`No response loading ${url}`)
      }
      if (!response.ok()) {
        const status = response.status()
        throw failure(
          `HTTP ${status} loading ${url}`,
          [408, 429, 500, 502, 503, 504].includes(status) ? 75 : 1,
        )
      }

      const screenshotPath = join(outputDir, `final-${name}.png`)
      try {
        await page.locator('body').waitFor({ state: 'visible' })
        await page.waitForFunction(
          () => window.__APP_READY__ === true,
          undefined,
          { timeout: 15000 },
        )
        await page.evaluate(() => document.fonts.ready)
        await page.waitForTimeout(400)

        const text = (await page.locator('body').innerText()).trim()
        if (text.length < 10) {
          throw failure('Rendered page is blank.', 1)
        }
        if (!browser.isConnected()) {
          throw temporary('Browser disconnected before capture.')
        }

        await page.screenshot({ path: screenshotPath, timeout: 30000 })
        if (statSync(screenshotPath).size < 24) {
          throw failure(`Screenshot is invalid: ${screenshotPath}`, 1)
        }
      } catch (error) {
        if (error.exitCode) throw error
        if (error.name === 'TimeoutError' || !browser.isConnected()) {
          throw temporary(`Timed out rendering ${name}: ${error.message}`, error)
        }
        throw failure(`Failed to capture ${name}: ${error.message}`, 1, error)
      }

      console.log(`Captured ${name}: ${screenshotPath}`)
    } finally {
      await page?.close().catch(() => {})
    }
  }
} catch (error) {
  console.error(error.stack || error)
  exitCode = error.exitCode || 1
} finally {
  if (browser) {
    try {
      await browser.close()
    } catch (error) {
      console.error(`Could not close browser: ${error.message}`)
      exitCode ||= 75
    }
  }
}

process.exit(exitCode)
