'use strict';

export const TELEGRAM_TOKEN = process.env.TELEGRAM_TOKEN
export const TELEGRAM_CHAT_ID = process.env.TELEGRAM_CHAT_ID
export const TELEGRAM_CHANNEL_ID = process.env.TELEGRAM_CHANNEL_ID

/** Куда шлём уведомления: личный чат, а при его отсутствии — группа/канал. */
export const TELEGRAM_TARGET_ID = TELEGRAM_CHAT_ID || TELEGRAM_CHANNEL_ID

export const HOST = 'www.gosuslugi.ru'
export const ORDER_ID = process.env.GOSUSLUGI_ORDER_ID || '7934451200'

export const COOKIES_FILE_NAME = 'cookies.txt'
export const STATE_FILE_NAME = 'state.json'

export const COOKIES_FILE =
  process.env.GOSUSLUGI_COOKIES || new URL(`./${COOKIES_FILE_NAME}`, import.meta.url).pathname
export const STATE_FILE = new URL(`./${STATE_FILE_NAME}`, import.meta.url).pathname

export const ORDER_API_URL = `https://${HOST}/api/lk/v1/orders/${ORDER_ID}`
export const ORDER_PAGE_URL = `https://${HOST}/600102/1/booking?parentOrderId=${ORDER_ID}`
export const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36'

export const POLL_MIN_MS = 2 * 60 * 1000
export const POLL_MAX_MS = 4 * 60 * 1000
export const REQUEST_TIMEOUT_MS = 30 * 1000

/** За сколько до конца сессии предупреждать, что пора обновить cookie-файл. */
export const SESSION_WARNING_MS = 3 * 60 * 1000
