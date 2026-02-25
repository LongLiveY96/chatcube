import { symbolRegister } from '@kit.UIDesignKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { resourceManager } from '@kit.LocalizationKit'

/**
 * 统一的 Symbol 资源注册入口，避免重复注册和分散异常处理。
 */
export class SymbolRegistry {
  private static registerStates: Map<string, boolean> = new Map<string, boolean>()

  static registerOnce(key: string, ttfSrc: resourceManager.Resource, jsonSrc: resourceManager.Resource): boolean {
    const cachedResult = SymbolRegistry.registerStates.get(key)
    if (cachedResult !== undefined) {
      return cachedResult
    }

    let result = false
    try {
      result = symbolRegister.registerSymbol(ttfSrc, jsonSrc)
    } catch (error) {
      const err = error as BusinessError
      console.error('SymbolRegistry', `register failed, key=${key}, code=${err.code}, message=${err.message}`)
      result = false
    }

    SymbolRegistry.registerStates.set(key, result)
    return result
  }

  static reset(key: string): void {
    SymbolRegistry.registerStates.delete(key)
  }

  static resetAll(): void {
    SymbolRegistry.registerStates.clear()
  }
}
