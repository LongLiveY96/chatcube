# HarmonyOS ArkTS 开发提示词

你正在为 HarmonyOS 应用开发相关功能。请严格遵循以下规则。

---

## 重要：文档查询

当遇到以下情况时，**必须先使用 `search_arkts_docs` 工具查询官方文档**：
- 不确定某个 API 的用法、参数或返回值
- 不确定某个组件的属性或事件
- 需要查看代码示例
- 遇到编译错误需要排查

```
示例：用户问 "Navigation 怎么用？"
→ 调用：search_arkts_docs({ query: "Navigation 路由" })
→ 获取 objectId 后调用：get_arkts_doc({ objectId: "xxx" })
```

**禁止猜测或自行构造 API，必须基于官方文档。**

---

## ArkTS 语法约束速查表

> 违反以下约束将导致编译失败

### 类型系统

| 不支持 | 替代方案 | 示例 |
|-------|---------|------|
| `any` / `unknown` | 显式指定类型 | `let x: string = ''` |
| `as const` | 显式类型标注 | `const x: 'a' = 'a'` |
| 索引访问类型 `T[K]` | 使用类型名称 | 定义具体接口 |
| 条件类型 `T extends U ? X : Y` | 使用继承或 Object | - |
| 交叉类型 `A & B` | 使用继承 | `class C extends A implements B` |
| 映射类型 | 使用常规类 | - |
| `typeof` 用于类型标注 | 显式类型声明 | `let y: MyClass` |
| 结构化类型 | 继承/接口/类型别名 | - |

### 变量与声明

| 不支持 | 替代方案 | 示例 |
|-------|---------|------|
| `var` | `let` / `const` | `let x = 1` |
| 解构赋值 `{a, b} = obj` | 逐个赋值 | `let a = obj.a; let b = obj.b` |
| 解构参数 | 直接传参 | `function f(obj: T) { let a = obj.a }` |
| 确定性赋值 `let v!: T` | 带初始化声明 | `let v: T = defaultValue` |

### 函数

| 不支持 | 替代方案 | 示例 |
|-------|---------|------|
| `function` 表达式 | 箭头函数 | `const fn = () => {}` |
| 嵌套函数 | 箭头函数(lambda) | `const inner = () => {}` |
| 生成器函数 | `async/await` | - |
| `Function.apply/call/bind` | OOP 风格 | 使用类方法 |
| 独立函数中的 `this` | 仅在实例方法中使用 | - |

### 对象与类

| 不支持 | 替代方案 | 示例 |
|-------|---------|------|
| 对象字面量作为类型 | 显式声明 class/interface | `interface MyData { ... }` |
| 动态属性访问 `obj["key"]` | 点语法 `obj.key` | - |
| `delete` 删除属性 | 设为 `null` | `obj.prop = null` |
| 索引签名 `[key: string]` | 使用数组或 Map | `Array<T>` / `Map<K,V>` |
| 构造函数中声明字段 | 类体内声明 | 见下方示例 |
| `#private` 私有字段 | `private` 关键字 | `private field: T` |
| 类作为值传递 | 类仅作为类型 | - |

```typescript
// ❌ 错误：构造函数中声明字段
class Wrong {
  constructor(public name: string) {}
}

// ✅ 正确：类体内声明
class Right {
  name: string = ''
  constructor(name: string) {
    this.name = name
  }
}
```

### 循环与运算符

| 不支持 | 替代方案 |
|-------|---------|
| `for...in` | 普通 `for` 循环或 `forEach` |
| `in` 运算符 | `instanceof` |
| `is` 类型守卫 | `instanceof` + `as` 转换 |
| 逗号运算符(for 循环外) | 分开写语句 |

### 模块与导入

| 不支持 | 替代方案 |
|-------|---------|
| `require()` | `import` 语法 |
| `export = ` | `export` / `export default` |
| 导入断言 | 普通 `import` |
| 通配符模块名 | 具体路径导入 |
| `globalThis` | 模块导出/导入 |

### 其他限制

| 不支持 | 说明 |
|-------|------|
| JSX | 使用 ArkUI 声明式语法 |
| `Symbol()` | 仅支持 `Symbol.iterator` |
| 声明合并 | 保持定义紧凑 |
| 多个静态代码块 | 合并为一个 |
| `new.target` | 不支持 |
| `with` 语句 | 不支持 |

---

## HarmonyOS API 使用规范

### 必须遵守

1. **优先使用官方 API** - 组件、动画、系统能力均使用 HarmonyOS 官方提供的
2. **确认 API Level** - 调用前确认 API 的版本支持和设备兼容性
3. **添加 import** - 使用 API 前确认文件头是否需要导入
4. **配置权限** - 在 `module.json5` 中配置所需权限
5. **管理依赖** - 在 `oh-package.json5` 中添加依赖配置

### 组件使用

```typescript
// @Component vs @ComponentV2 - 与项目已有代码保持一致
@Component
struct MyComponent {
  @State count: number = 0

  build() {
    Column() {
      Text($r('app.string.hello'))  // ✅ 使用资源引用
      Text('Hello')                  // ❌ 避免硬编码字符串
    }
  }
}
```

### 资源管理

- UI 文本使用 `$r('app.string.xxx')` 引用资源
- 颜色使用 `$r('app.color.xxx')` 引用资源
- 新增字符串时，所有语言包都要添加
- 新增颜色时，同时添加浅色/深色主题值

---

## ArkUI 动画规范

### 推荐做法

```typescript
@Component
struct AnimatedComponent {
  @State scale: number = 1

  build() {
    Column() {
      Button('Animate')
        .scale({ x: this.scale, y: this.scale })
        .onClick(() => {
          animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
            this.scale = this.scale === 1 ? 1.2 : 1
          })
        })
    }
    .renderGroup(true)  // 复杂组件启用渲染组
  }
}
```

### 性能规则

| 规则 | 说明 |
|-----|------|
| 使用 `@State` 驱动 | 通过状态变量触发动画 |
| 启用 `renderGroup(true)` | 复杂子组件减少渲染批次 |
| 避免动画中改变布局属性 | `width`/`height`/`padding`/`margin` 会严重影响性能 |
| 优先使用 `transform` 属性 | `scale`/`rotate`/`translate` 性能更好 |

### 可动画属性(推荐)

- `opacity` - 透明度
- `scale` - 缩放
- `rotate` - 旋转
- `translate` - 位移
- `backgroundColor` - 背景色

### 避免动画的属性

- `width` / `height`
- `padding` / `margin`
- `position` (改用 `translate`)

---

## 常见错误速查

| 错误信息 | 原因 | 解决方案 |
|---------|------|---------|
| `Type 'any' is not supported` | 使用了 any | 指定具体类型 |
| `Destructuring is not supported` | 使用了解构 | 逐个赋值 |
| `'var' is not supported` | 使用了 var | 改用 let |
| `Indexed access is not supported` | 使用了 obj["key"] | 改用 obj.key |
| `Function expression is not supported` | 使用了 function() | 改用箭头函数 |

---

## 资源参考

- Symbol 和 Color 常量：查看 `sysResource.js`（文件较大，建议搜索关键字）
- 官方文档：使用 `search_arkts_docs` 工具搜索
