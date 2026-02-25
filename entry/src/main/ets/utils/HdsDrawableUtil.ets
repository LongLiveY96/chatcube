import { LayeredDrawableDescriptor } from '@kit.ArkUI'
import { hdsDrawable } from '@kit.UIDesignKit'
import { image } from '@kit.ImageKit'
import { BusinessError } from '@kit.BasicServicesKit'

/**
 * hdsDrawable 统一入口：集中错误处理，避免页面侧直接耦合底层接口。
 */
export class HdsDrawableUtil {
  static async getLayeredIconAsync(bundleName: string, layeredDescriptor: LayeredDrawableDescriptor,
    size: number, hasBorder: boolean = false): Promise<image.PixelMap | null> {
    try {
      return await hdsDrawable.getHdsLayeredIconAsync(bundleName, layeredDescriptor, size, hasBorder)
    } catch (error) {
      const err = error as BusinessError
      console.error('HdsDrawableUtil', `getLayeredIconAsync failed, code=${err.code}, message=${err.message}`)
      return null
    }
  }

  static async getLayeredIconsAsync(icons: Array<hdsDrawable.LayeredIcon>,
    options: hdsDrawable.Options): Promise<Array<hdsDrawable.ProcessedIcon>> {
    try {
      return await hdsDrawable.getHdsLayeredIcons(icons, options)
    } catch (error) {
      const err = error as BusinessError
      console.error('HdsDrawableUtil', `getLayeredIconsAsync failed, code=${err.code}, message=${err.message}`)
      return []
    }
  }
}
