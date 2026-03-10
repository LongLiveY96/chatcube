import { ChatSession, MessageAttachment } from '../models/ChatModels'

export const SESSION_DRAFT_TAG_TEXT: string = '草稿'
export const SESSION_DRAFT_PREFIX: string = `[${SESSION_DRAFT_TAG_TEXT}]`

function normalizePreviewText(text: string): string {
  return text.replace(/\s+/g, ' ').trim()
}

function getDraftAttachmentPreview(attachments: MessageAttachment[]): string {
  for (let i = 0; i < attachments.length; i++) {
    const normalizedName = normalizePreviewText(attachments[i].name)
    if (normalizedName !== '') {
      return normalizedName
    }
  }
  if (attachments.length === 0) {
    return ''
  }
  if (attachments.length === 1) {
    return '附件'
  }
  return `${attachments.length} 个附件`
}

export function hasSessionDraftContent(session: ChatSession): boolean {
  return normalizePreviewText(session.draftText) !== '' || session.draftAttachments.length > 0
}

export function getSessionPreviewBodyText(session: ChatSession): string {
  if (hasSessionDraftContent(session)) {
    const normalizedDraftText = normalizePreviewText(session.draftText)
    if (normalizedDraftText !== '') {
      return normalizedDraftText
    }
    return getDraftAttachmentPreview(session.draftAttachments)
  }
  return normalizePreviewText(session.lastMessagePreview)
}

export function getSessionDisplayPreviewText(session: ChatSession): string {
  const bodyText = getSessionPreviewBodyText(session)
  if (hasSessionDraftContent(session)) {
    return bodyText !== '' ? `${SESSION_DRAFT_PREFIX} ${bodyText}` : SESSION_DRAFT_PREFIX
  }
  return bodyText
}
