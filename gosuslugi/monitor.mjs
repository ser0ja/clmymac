'use strict';

import { isExpiringSoon, readSession } from './cookies.mjs'
import {
  COOKIES_FILE,
  COOKIES_FILE_NAME,
  HOST,
  ORDER_ID,
  ORDER_PAGE_URL,
  POLL_MAX_MS,
  POLL_MIN_MS,
  SESSION_WARNING_MS,
} from './constants.mjs'
import { SessionExpiredError, diffSnapshots, fetchOrder, isInviteReady, toSnapshot } from './order-api.mjs'
import { readState, writeState } from './state.mjs'
import { sendMessage } from './telegram.mjs'

const MS_IN_SECOND = 1000
const MS_IN_MINUTE = 60 * MS_IN_SECOND

const randomDelayMs = () => POLL_MIN_MS + Math.floor(Math.random() * (POLL_MAX_MS - POLL_MIN_MS + 1))

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

const stamp = () => new Date().toLocaleTimeString('ru-RU')

/** Сколько осталось жить текущей сессии — для лога. */
const formatSessionLeft = (expiresAt) => {
  if (expiresAt === null) return 'срок сессии неизвестен'

  const leftMinutes = Math.round((expiresAt - Date.now()) / MS_IN_MINUTE)
  return leftMinutes > 0 ? `куки живут ещё ${leftMinutes} мин` : 'куки истекли'
}

const formatChanges = (previous, current, fields) =>
  fields
    .map((field) => `• <b>${field}</b>: ${JSON.stringify(previous[field])} → ${JSON.stringify(current[field])}`)
    .join('\n')

const notifyChange = async (previous, current, fields) => {
  const header = isInviteReady(current)
    ? '🔔 <b>Госуслуги: ответ ведомства получен — можно записываться!</b>'
    : '📄 <b>Госуслуги: изменился статус заявления</b>'

  await sendMessage(
    `${header}\n\nЗаявление <code>${ORDER_ID}</code>\n\n${formatChanges(previous, current, fields)}\n\n<a href="${ORDER_PAGE_URL}">Открыть на портале</a>`,
  )
}

/** Предупреждает один раз на каждую сессию, что скоро придётся обновить куки. */
const warnBeforeExpiry = async (expiresAt, warnedFor) => {
  if (warnedFor === expiresAt || !isExpiringSoon(expiresAt, SESSION_WARNING_MS)) return warnedFor

  const leftMs = expiresAt - Date.now()

  const sent = await sendMessage(
    `⏳ <b>Госуслуги: сессия истекает через ${Math.max(0, Math.round(leftMs / MS_IN_MINUTE))} мин</b>\n\n` +
      `Обнови <code>${COOKIES_FILE_NAME}</code> — иначе мониторинг заявления <code>${ORDER_ID}</code> встанет.`,
  )
  console.log(`[${stamp()}] предупреждение об истечении сессии ${sent ? 'отправлено' : 'не отправлено'}`)

  return sent ? expiresAt : warnedFor
}

const checkOnce = async (previous) => {
  const session = await readSession(COOKIES_FILE, HOST)
  const current = toSnapshot(await fetchOrder(session.header))

  if (previous === null) {
    console.log(`[${stamp()}] базовое состояние сохранено:`, current)
    await writeState(current)
    return { snapshot: current, expiresAt: session.expiresAt }
  }

  const changed = diffSnapshots(previous, current)
  if (changed.length === 0) {
    console.log(`[${stamp()}] без изменений`)
    return { snapshot: previous, expiresAt: session.expiresAt }
  }

  console.log(`[${stamp()}] изменились поля: ${changed.join(', ')}`)
  await notifyChange(previous, current, changed)
  await writeState(current)
  return { snapshot: current, expiresAt: session.expiresAt }
}

const run = async () => {
  console.log(`Мониторинг заявления ${ORDER_ID}, интервал ${POLL_MIN_MS / MS_IN_SECOND}–${POLL_MAX_MS / MS_IN_SECOND} с`)

  let previous = (await readState())?.snapshot ?? null
  let warnedFor = null
  let sessionAlertSent = false

  for (;;) {
    let expiresAt = null

    try {
      const result = await checkOnce(previous)
      previous = result.snapshot
      expiresAt = result.expiresAt
      warnedFor = await warnBeforeExpiry(expiresAt, warnedFor)
      sessionAlertSent = false
    } catch (error) {
      console.error(`[${stamp()}] ${error.message}`)

      if (error instanceof SessionExpiredError && !sessionAlertSent) {
        sessionAlertSent = await sendMessage(
          `⚠️ <b>Госуслуги: сессия истекла</b>\n\nОбнови <code>${COOKIES_FILE_NAME}</code> — мониторинг заявления <code>${ORDER_ID}</code> остановлен до этого.`,
        )
      }
    }

    const delayMs = randomDelayMs()
    console.log(`[${stamp()}] ${formatSessionLeft(expiresAt)}; следующая проверка через ${Math.round(delayMs / MS_IN_SECOND)} с`)
    await sleep(delayMs)
  }
}

await run()
