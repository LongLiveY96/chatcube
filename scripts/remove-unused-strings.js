/**
 * 删除未使用的字符串资源
 * 用法: node scripts/remove-unused-strings.js
 */

const fs = require('fs')
const path = require('path')

// 要删除的字符串列表（真正废弃的，不含未来功能和系统配置）
const TO_DELETE = new Set([
  // 旧版标签
  'model_tag_openai',
  'model_tag_claude',
  'model_tag_gemini',
  'model_tag_other',
  // 旧版菜单
  'menu_copy',
  'menu_regenerate',
  'menu_edit',
  'menu_read_aloud',
  'menu_stop_read_aloud',
  // 旧版 UI 文案
  'enabled_services',
  'available_models',
  'save_config',
  'refresh_list',
  'connected',
  'recommended',
  'model_list',
  'settings_dark_mode',
  'settings_dark_mode_desc',
  'settings_notifications_enabled',
  'import_success',
  'translation_clear',
  'message_saved',
  'save_failed_retry',
  'provider_moved_up',
  'provider_moved_down',
  'disabled_services',
  'provider_disabled_badge',
  'provider_menu_move_up',
  'provider_menu_move_down',
  'provider_menu_enable',
  'provider_menu_disable',
  'api_style_openai_desc',
  'api_style_anthropic_desc',
  'api_style_google_desc',
  'model_input_placeholder',
  'model_picker_select_all',
  'model_picker_added',
  'function_calling_not_supported',
  'about_wechat_support_desc',
  // 平板空状态
  'tablet_provider_detail_empty_title',
  'tablet_provider_detail_empty_desc',
  'tablet_settings_detail_empty_title',
  'tablet_settings_detail_empty_desc',
  // 权限相关（未使用）
  'permission_publish_notification'
])

function processFile(filePath, locale) {
  console.log(`\n处理 ${locale}: ${filePath}`)

  const content = fs.readFileSync(filePath, 'utf-8')
  const json = JSON.parse(content)

  const originalCount = json.string.length
  const before = new Set(json.string.map(s => s.name))

  // 过滤掉要删除的字符串
  json.string = json.string.filter(item => !TO_DELETE.has(item.name))

  const after = new Set(json.string.map(s => s.name))
  const deleted = [...before].filter(name => !after.has(name))

  console.log(`  原始: ${originalCount} 个`)
  console.log(`  删除: ${deleted.length} 个`)
  console.log(`  剩余: ${json.string.length} 个`)

  if (deleted.length > 0) {
    console.log(`  已删除: ${deleted.join(', ')}`)
    fs.writeFileSync(filePath, JSON.stringify(json, null, 2), 'utf-8')
    console.log(`  ✅ 已保存`)
  } else {
    console.log(`  ⏭️ 无需修改`)
  }

  return deleted
}

function main() {
  const projectRoot = path.resolve(__dirname, '..')

  console.log('=== 删除未使用的字符串资源 ===')
  console.log(`计划删除 ${TO_DELETE.size} 个字符串`)

  const basePath = path.join(projectRoot, 'entry/src/main/resources/base/element/string.json')
  const zhPath = path.join(projectRoot, 'entry/src/main/resources/zh_CN/element/string.json')

  const baseDeleted = processFile(basePath, 'base')
  const zhDeleted = processFile(zhPath, 'zh_CN')

  console.log('\n=== 完成 ===')
  console.log(`共删除 ${baseDeleted.length} 个字符串`)
}

main()
