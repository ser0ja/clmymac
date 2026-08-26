'use strict';

import assert from 'node:assert/strict'
import { mkdtemp, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'

import { readSession } from './cookies.mjs'

const HOST = 'www.gosuslugi.ru'
const inSeconds = (seconds) => Math.floor(Date.now() / 1000) + seconds

const line = (domain, expires, name, value) => [domain, 'TRUE', '/', 'TRUE', expires, name, value].join('\t')

const writeCookieFile = async (lines) => {
  const dir = await mkdtemp(join(tmpdir(), 'cookies-'))
  const path = join(dir, 'cookies.txt')
  await writeFile(path, ['# Netscape HTTP Cookie File', ...lines].join('\n'))
  return path
}

test('собирает заголовок и срок жизни авторизации', async () => {
  const path = await writeCookieFile([
    line('.gosuslugi.ru', inSeconds(3600), 'acc_t', 'token'),
    line('.gosuslugi.ru', inSeconds(1800), 'si', 'session'),
    line('.gosuslugi.ru', 0, 'nau', 'flag'),
  ])

  const { header, expiresAt } = await readSession(path, HOST)

  assert.equal(header, 'acc_t=token; si=session; nau=flag')
  assert.ok(Math.abs(expiresAt - (Date.now() + 1800 * 1000)) < 2000, 'берётся ближайшая из авторизационных кук')
})

test('пропускает HttpOnly-строки и куски чужих доменов', async () => {
  const path = await writeCookieFile([
    `#HttpOnly_${line('.gosuslugi.ru', inSeconds(600), 'acc_t', 'token')}`,
    line('.example.com', inSeconds(600), 'foreign', 'x'),
  ])

  const { header } = await readSession(path, HOST)

  assert.equal(header, 'acc_t=token')
})

test('отбрасывает протухшие куки', async () => {
  const path = await writeCookieFile([
    line('.gosuslugi.ru', inSeconds(-60), 'acc_t', 'old'),
    line('.gosuslugi.ru', inSeconds(600), 'nau', 'flag'),
  ])

  const { header, expiresAt } = await readSession(path, HOST)

  assert.equal(header, 'nau=flag')
  assert.equal(expiresAt, null, 'без авторизационных кук срок не определён')
})

test('падает, когда действующих кук не осталось', async () => {
  const path = await writeCookieFile([line('.gosuslugi.ru', inSeconds(-60), 'acc_t', 'old')])

  await assert.rejects(() => readSession(path, HOST), /экспортируй сессию заново/)
})

test('isExpiringSoon срабатывает только у границы и при известном сроке', async () => {
  const { isExpiringSoon } = await import('./cookies.mjs')
  const threshold = 15 * 60 * 1000

  assert.equal(isExpiringSoon(Date.now() + 10 * 60 * 1000, threshold), true)
  assert.equal(isExpiringSoon(Date.now() + 60 * 60 * 1000, threshold), false)
  assert.equal(isExpiringSoon(Date.now() - 60 * 1000, threshold), true, 'уже протухшая сессия тоже повод сказать')
  assert.equal(isExpiringSoon(null, threshold), false)
})
