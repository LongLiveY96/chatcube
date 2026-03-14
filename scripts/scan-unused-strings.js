/**
 * 扫描未使用的字符串资源
 * 用法: node scripts/scan-unused-strings.js
 */

const fs = require('fs')
const path = require('path')

// 读取 string.json 文件
function readStringNames(jsonPath) {
  const content = fs.readFileSync(jsonPath, 'utf-8')
  const json = JSON.parse(content)
  return json.string.map(item => item.name)
}

// 递归获取所有指定扩展名的文件
function getAllFiles(dir, extensions, files = []) {
  const items = fs.readdirSync(dir)
  for (const item of items) {
    const fullPath = path.join(dir, item)
    const stat = fs.statSync(fullPath)
    if (stat.isDirectory()) {
      getAllFiles(fullPath, extensions, files)
    } else if (extensions.some(ext => item.endsWith(ext))) {
      files.push(fullPath)
    }
  }
  return files
}

// 检查字符串是否在代码中使用
function isStringUsed(stringName, codeContent) {
  const patterns = [
    // ArkTS 代码中的引用: $r('app.string.xxx') 或 $r("app.string.xxx")
    new RegExp(`\\$r\\(['"]app\\.string\\.${escapeRegex(stringName)}['"]\\)`, 'g'),
    // 配置文件中的引用: $string:xxx
    new RegExp(`\\$string:${escapeRegex(stringName)}[^_a-zA-Z0-9]`, 'g'),
    // 也检查可能的原始字符串引用
    new RegExp(`app\\.string\\.${escapeRegex(stringName)}`, 'g')
  ]
  return patterns.some(pattern => pattern.test(codeContent))
}

function escapeRegex(string) {
  return string.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

function main() {
  const projectRoot = path.resolve(__dirname, '..')
  const baseStringsPath = path.join(projectRoot, 'entry/src/main/resources/base/element/string.json')
  const zhStringsPath = path.join(projectRoot, 'entry/src/main/resources/zh_CN/element/string.json')
  const etsDir = path.join(projectRoot, 'entry/src/main/ets')

  console.log('=== 扫描未使用的字符串资源 ===\n')

  // 读取所有字符串名称（使用 base 目录作为基准）
  const stringNames = readStringNames(baseStringsPath)
  console.log(`共 ${stringNames.length} 个字符串资源\n`)

  // 读取所有 .ets 文件内容
  const etsFiles = getAllFiles(etsDir, ['.ets'])
  console.log(`扫描 ${etsFiles.length} 个 .ets 文件...`)

  // 读取配置文件
  const configFiles = [
    path.join(projectRoot, 'entry/src/main/module.json5'),
    ...getAllFiles(path.join(projectRoot, 'entry/src/main/resources/base/profile'), ['.json5', '.json'])
  ]
  console.log(`扫描 ${configFiles.length} 个配置文件...\n`)

  // 合并所有代码内容
  let allCode = ''
  for (const file of etsFiles) {
    allCode += fs.readFileSync(file, 'utf-8') + '\n'
  }
  for (const file of configFiles) {
    if (fs.existsSync(file)) {
      allCode += fs.readFileSync(file, 'utf-8') + '\n'
    }
  }

  // 检查每个字符串是否被使用
  const unusedStrings = []
  const usedStrings = []

  for (const name of stringNames) {
    if (isStringUsed(name, allCode)) {
      usedStrings.push(name)
    } else {
      unusedStrings.push(name)
    }
  }

  console.log('=== 结果 ===\n')
  console.log(`已使用: ${usedStrings.length}`)
  console.log(`未使用: ${unusedStrings.length}\n`)

  if (unusedStrings.length > 0) {
    console.log('未使用的字符串资源:')
    unusedStrings.forEach(name => {
      console.log(`  - ${name}`)
    })
  }

  // 额外检查：zh_CN 是否有缺失的翻译
  const zhStrings = readStringNames(zhStringsPath)
  const missingInZh = stringNames.filter(name => !zhStrings.includes(name))
  const extraInZh = zhStrings.filter(name => !stringNames.includes(name))

  if (missingInZh.length > 0) {
    console.log('\n⚠️ zh_CN 缺失的翻译:')
    missingInZh.forEach(name => {
      console.log(`  - ${name}`)
    })
  }

  if (extraInZh.length > 0) {
    console.log('\n⚠️ zh_CN 多余的字符串:')
    extraInZh.forEach(name => {
      console.log(`  - ${name}`)
    })
  }

  // 输出 JSON 格式的未使用字符串列表（便于后续处理）
  const outputPath = path.join(projectRoot, 'scripts/unused-strings.json')
  fs.writeFileSync(outputPath, JSON.stringify(unusedStrings, null, 2))
  console.log(`\n未使用字符串列表已保存到: ${outputPath}`)
}

main()
