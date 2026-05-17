import { generateBarcode, scanCore } from '@kit.ScanKit'
import { image } from '@kit.ImageKit'

const DEFAULT_QR_SIZE: number = 720
const DEFAULT_QR_MARGIN: number = 4
const MIN_QR_CONTENT_LEN: number = 1

class ProviderShareGenerator {
  /**
   * 生成 QR PixelMap。调用方负责在不再展示时 release()。
   */
  async generateQrPixelMap(text: string): Promise<image.PixelMap> {
    if (text.length < MIN_QR_CONTENT_LEN) {
      throw new Error('QR content is empty')
    }
    try {
      const options: generateBarcode.CreateOptions = {
        scanType: scanCore.ScanType.QR_CODE,
        height: DEFAULT_QR_SIZE,
        width: DEFAULT_QR_SIZE,
        margin: DEFAULT_QR_MARGIN
      }
      return await generateBarcode.createBarcode(text, options)
    } catch (err) {
      throw new Error(`generateQrPixelMap failed: ${JSON.stringify(err)}`)
    }
  }
}

let generatorInstance: ProviderShareGenerator | null = null

export function getProviderShareGenerator(): ProviderShareGenerator {
  if (generatorInstance === null) {
    generatorInstance = new ProviderShareGenerator()
  }
  return generatorInstance
}
