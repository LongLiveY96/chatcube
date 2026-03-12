import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit'

export async function saveRawfileImageToAlbum(
  context: common.UIAbilityContext,
  rawFileName: string,
  titlePrefix: string
): Promise<void> {
  const rawFileData = context.resourceManager.getRawFileContentSync(rawFileName)
  const extension = rawFileName.toLowerCase().endsWith('.png') ? 'png' : 'jpg'
  const tempPath = `${context.cacheDir}/${titlePrefix}_${Date.now()}.${extension}`
  const tempFile = fileIo.openSync(tempPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY)
  fileIo.writeSync(tempFile.fd, rawFileData.buffer)
  fileIo.closeSync(tempFile)

  try {
    const tempUriStr = fileUri.getUriFromPath(tempPath)
    const config: photoAccessHelper.PhotoCreationConfig = {
      title: `${titlePrefix}_${Date.now()}`,
      fileNameExtension: extension,
      photoType: photoAccessHelper.PhotoType.IMAGE,
      subtype: photoAccessHelper.PhotoSubtype.DEFAULT
    }
    const phAccessHelper = photoAccessHelper.getPhotoAccessHelper(context)
    const desFileUris = await phAccessHelper.showAssetsCreationDialog([tempUriStr], [config])
    if (desFileUris.length === 0) {
      throw new Error('User cancelled save')
    }

    const srcFile = fileIo.openSync(tempUriStr, fileIo.OpenMode.READ_ONLY)
    const desFile = fileIo.openSync(desFileUris[0], fileIo.OpenMode.WRITE_ONLY)
    fileIo.copyFileSync(srcFile.fd, desFile.fd)
    fileIo.closeSync(srcFile)
    fileIo.closeSync(desFile)
  } finally {
    try {
      fileIo.unlinkSync(tempPath)
    } catch (_) {
      // ignore cleanup error
    }
  }
}
