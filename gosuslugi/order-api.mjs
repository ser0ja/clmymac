'use strict';

import { HOST, ORDER_API_URL, REQUEST_TIMEOUT_MS, USER_AGENT } from './constants.mjs'

export class SessionExpiredError extends Error {}

const HTTP_UNAUTHORIZED = 401
const HTTP_FORBIDDEN = 403

/** Поля заявления, изменение которых означает движение по услуге. */
const WATCHED_FIELDS = [
  'orderStatusId',
  'smevMessageId',
  'hasActiveInviteToEqueue',
  'checkQueue',
  'updated',
  'currentStatusHistoryId',
  'hasNewStatus',
]

const countOf = (value) => (Array.isArray(value) ? value.length : 0)

/** Сжимает ответ API до набора значимых признаков — по нему и сравниваем. */
export const toSnapshot = (order) => ({
  ...Object.fromEntries(WATCHED_FIELDS.map((field) => [field, order[field] ?? null])),
  statusesCount: countOf(order.statuses),
  eQueueEventsCount: countOf(order.eQueueEvents),
  responseFilesCount: countOf(order.orderResponseFiles),
  lastStatusTitle: order.statuses?.at(-1)?.title ?? null,
})

/** Ответ ведомства пришёл — можно записываться на приём. */
export const isInviteReady = (snapshot) =>
  snapshot.hasActiveInviteToEqueue === true ||
  snapshot.checkQueue === true ||
  snapshot.eQueueEventsCount > 0 ||
  (snapshot.smevMessageId !== null && snapshot.smevMessageId !== 'WAIT_RESPONSE')

/** Забирает заявление из ЛК Госуслуг. Бросает SessionExpiredError, если сессия протухла. */
export const fetchOrder = async (cookieHeader) => {
  const res = await fetch(`${ORDER_API_URL}?_=${Date.now()}`, {
    headers: {
      cookie: cookieHeader,
      accept: 'application/json, text/plain, */*',
      'accept-language': 'ru-RU,ru;q=0.9,en-US;q=0.8',
      'user-agent': USER_AGENT,
      referer: `https://${HOST}/`,
      'sec-fetch-dest': 'empty',
      'sec-fetch-mode': 'cors',
      'sec-fetch-site': 'same-origin',
    },
    redirect: 'manual',
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  })

  if (res.status === HTTP_UNAUTHORIZED || res.status === HTTP_FORBIDDEN) {
    throw new SessionExpiredError(`сессия недействительна (HTTP ${res.status})`)
  }

  if (!res.ok) {
    throw new Error(`неожиданный ответ API: HTTP ${res.status}`)
  }

  const contentType = res.headers.get('content-type') ?? ''
  if (!contentType.includes('application/json')) {
    throw new Error(`вместо JSON пришёл ${contentType.split(';')[0] || 'пустой ответ'} — портал включил антибот-проверку`)
  }

  return res.json()
}

/** Имена полей снапшота, значения которых различаются. */
export const diffSnapshots = (previous, current) =>
  Object.keys(current).filter((field) => JSON.stringify(previous[field]) !== JSON.stringify(current[field]))
