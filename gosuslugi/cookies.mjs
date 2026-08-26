'use strict';

import { readFile } from 'node:fs/promises'

const HTTP_ONLY_PREFIX = '#HttpOnly_'
const FIELD_DOMAIN = 0
const FIELD_EXPIRES = 4
const FIELD_NAME = 5
const FIELD_VALUE = 6
const FIELDS_COUNT = 7
const MS_IN_SECOND = 1000

/** Куки, на которых держится авторизация — по ним считаем срок жизни сессии. */
const AUTH_COOKIES = ['acc_t', 'si']

const parseLine = (line) => {
  const cleaned = line.startsWith(HTTP_ONLY_PREFIX) ? line.slice(HTTP_ONLY_PREFIX.length) : line
  if (!cleaned.trim() || cleaned.startsWith('#')) return null

  const fields = cleaned.split('\t')
  if (fields.length < FIELDS_COUNT) return null

  return {
    domain: fields[FIELD_DOMAIN].replace(/^\./, ''),
    expires: Number(fields[FIELD_EXPIRES]) || 0,
    name: fields[FIELD_NAME],
    value: fields[FIELD_VALUE],
  }
}

/**
 * Читает cookie-файл в формате Netscape (экспорт из браузера).
 * Возвращает заголовок Cookie и момент, когда протухнет авторизация
 * (null — авторизационных кук уже нет).
 */
export const readSession = async (filePath, host) => {
  const raw = await readFile(filePath, 'utf8')
  const nowSeconds = Math.floor(Date.now() / MS_IN_SECOND)

  const cookies = raw
    .split('\n')
    .map(parseLine)
    .filter((cookie) => cookie !== null)
    .filter((cookie) => host === cookie.domain || host.endsWith(`.${cookie.domain}`))
    .filter((cookie) => cookie.expires === 0 || cookie.expires > nowSeconds)

  if (cookies.length === 0) {
    throw new Error(`В ${filePath} нет действующих cookie для ${host} — экспортируй сессию заново`)
  }

  const authExpiry = cookies
    .filter((cookie) => AUTH_COOKIES.includes(cookie.name))
    .map((cookie) => cookie.expires)
    .filter((expires) => expires > 0)

  return {
    header: cookies.map(({ name, value }) => `${name}=${value}`).join('; '),
    expiresAt: authExpiry.length > 0 ? Math.min(...authExpiry) * MS_IN_SECOND : null,
  }
}

/** Пора ли предупреждать, что сессия скоро протухнет. */
export const isExpiringSoon = (expiresAt, thresholdMs) =>
  expiresAt !== null && expiresAt - Date.now() <= thresholdMs
