'use strict';

import { TELEGRAM_TOKEN, TELEGRAM_TARGET_ID } from './constants.mjs'

const API_BASE = 'https://api.telegram.org'

/** Отправляет сообщение в целевой чат. Возвращает true при успехе. */
export const sendMessage = async (text) => {
  if (!TELEGRAM_TOKEN || !TELEGRAM_TARGET_ID) {
    console.error('[telegram] нет TELEGRAM_TOKEN или чата назначения — сообщение не отправлено')
    return false
  }

  try {
    const res = await fetch(`${API_BASE}/bot${TELEGRAM_TOKEN}/sendMessage`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        chat_id: TELEGRAM_TARGET_ID,
        text,
        parse_mode: 'HTML',
        disable_web_page_preview: true,
      }),
    })

    if (!res.ok) {
      const { description } = await res.json().catch(() => ({}))
      console.error(`[telegram] HTTP ${res.status}: ${description ?? 'нет описания'}`)
      return false
    }

    return true
  } catch (error) {
    console.error(`[telegram] сбой отправки: ${error.message}`)
    return false
  }
}
