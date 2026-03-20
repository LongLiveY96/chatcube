import { hapTasks } from '@ohos/hvigor-ohos-plugin'
import type { HvigorPlugin } from '@ohos/hvigor'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'

const OHOS_TEST_MAIN_ELEMENT = 'TestAbility'
const OHOS_TEST_PACKAGE_NAME = 'entry'

type HvigorNodeWithPath = Parameters<HvigorPlugin['apply']>[0] & {
  getNodePath?: () => string
}

type OhosTestModuleSource = {
  module?: {
    name?: string
    type?: string
    deviceTypes?: string[]
    deliveryWithInstall?: boolean
    installationFree?: boolean
  }
}

function resolveModulePath(node: HvigorNodeWithPath): string {
  if (typeof node.getNodePath === 'function') {
    return node.getNodePath()
  }
  return join(process.cwd(), 'entry')
}

function writeFileIfChanged(filePath: string, content: string): void {
  mkdirSync(dirname(filePath), { recursive: true })
  if (existsSync(filePath)) {
    const existingContent = readFileSync(filePath, 'utf-8')
    if (existingContent === content) {
      return
    }
  }
  writeFileSync(filePath, content, 'utf-8')
}

function readJsonFile<T extends object>(filePath: string): T | null {
  if (!existsSync(filePath)) {
    return null
  }
  return JSON.parse(readFileSync(filePath, 'utf-8')) as T
}

function ensureGeneratedOhosTestModuleJson(modulePath: string): void {
  const sourceConfig = readJsonFile<OhosTestModuleSource>(join(modulePath, 'src', 'ohosTest', 'module.json5'))
  if (sourceConfig === null || sourceConfig.module === undefined) {
    return
  }

  const moduleConfig = sourceConfig.module
  const generatedConfig = {
    module: {
      name: moduleConfig.name ?? 'entry_test',
      type: moduleConfig.type ?? 'feature',
      deviceTypes: moduleConfig.deviceTypes ?? ['phone', 'tablet'],
      deliveryWithInstall: moduleConfig.deliveryWithInstall ?? true,
      installationFree: moduleConfig.installationFree ?? false,
      packageName: OHOS_TEST_PACKAGE_NAME,
      mainElement: OHOS_TEST_MAIN_ELEMENT,
      pages: '$profile:test_pages',
      abilities: [
        {
          name: OHOS_TEST_MAIN_ELEMENT,
          srcEntry: './testability/TestAbility.ets',
          description: '$string:TestAbility_desc',
          label: '$string:TestAbility_label',
          exported: true
        }
      ],
      requestPermissions: [
        {
          name: 'ohos.permission.INTERNET',
          reason: '$string:use_network'
        }
      ],
      virtualMachine: 'ark13.0.1.0',
      compileMode: 'esmodule',
      dependencies: []
    }
  }

  writeFileIfChanged(
    join(modulePath, '.test', 'default', 'intermediates', 'src', 'ohosTest', 'ets', 'module.json'),
    `${JSON.stringify(generatedConfig, null, 2)}\n`
  )
}

function ensureGeneratedOhosTestIndexPage(modulePath: string): void {
  const sourcePagePath = join(modulePath, 'src', 'ohosTest', 'ets', 'pages', 'Index.ets')
  if (!existsSync(sourcePagePath)) {
    return
  }

  writeFileIfChanged(
    join(modulePath, '.test', 'default', 'intermediates', 'src', 'ohosTest', 'ets', 'pages', 'Index.ets'),
    readFileSync(sourcePagePath, 'utf-8')
  )
}

function ensureTestAbilityCompatibilityProxy(modulePath: string): void {
  writeFileIfChanged(
    join(modulePath, '.test', 'default', 'intermediates', '.test', 'testability', 'TestAbility.ets'),
    `export { default } from '../../../../testability/TestAbility'\n`
  )
}

function ensureOhosTestCompatibilityArtifacts(modulePath: string): void {
  ensureGeneratedOhosTestModuleJson(modulePath)
  ensureGeneratedOhosTestIndexPage(modulePath)
  ensureTestAbilityCompatibilityProxy(modulePath)
}

const generatedTestArtifactsFixPlugin: HvigorPlugin = {
  pluginId: 'generated-test-artifacts-fix-plugin',
  apply(node) {
    node.afterNodeEvaluate(() => {
      ensureOhosTestCompatibilityArtifacts(resolveModulePath(node as HvigorNodeWithPath))
    })
  }
}

export default {
  system: hapTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: [generatedTestArtifactsFixPlugin] /* Custom plugin to extend the functionality of Hvigor. */
}
