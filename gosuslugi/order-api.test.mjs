'use strict';

import assert from 'node:assert/strict'
import { test } from 'node:test'

import { diffSnapshots, isInviteReady, toSnapshot } from './order-api.mjs'

const waitingOrder = {
  orderStatusId: 25,
  smevMessageId: 'WAIT_RESPONSE',
  hasActiveInviteToEqueue: false,
  checkQueue: false,
  updated: '2026-08-24T10:48:11.512+0300',
  currentStatusHistoryId: 34349872604,
  hasNewStatus: true,
  statuses: [],
  eQueueEvents: [],
  orderResponseFiles: [],
}

test('снапшот берёт отслеживаемые поля и длины коллекций', () => {
  const snapshot = toSnapshot({ ...waitingOrder, statuses: [{ title: 'Заявление получено' }] })

  assert.equal(snapshot.orderStatusId, 25)
  assert.equal(snapshot.statusesCount, 1)
  assert.equal(snapshot.lastStatusTitle, 'Заявление получено')
  assert.equal(snapshot.eQueueEventsCount, 0)
})

test('снапшот подставляет null для отсутствующих полей', () => {
  assert.equal(toSnapshot({}).smevMessageId, null)
  assert.equal(toSnapshot({}).lastStatusTitle, null)
})

test('ожидание ответа ведомства не считается приглашением', () => {
  assert.equal(isInviteReady(toSnapshot(waitingOrder)), false)
})

test('приглашение в очередь распознаётся', () => {
  assert.equal(isInviteReady(toSnapshot({ ...waitingOrder, hasActiveInviteToEqueue: true })), true)
  assert.equal(isInviteReady(toSnapshot({ ...waitingOrder, checkQueue: true })), true)
  assert.equal(isInviteReady(toSnapshot({ ...waitingOrder, eQueueEvents: [{ id: 1 }] })), true)
})

test('уход smevMessageId из WAIT_RESPONSE означает ответ ведомства', () => {
  assert.equal(isInviteReady(toSnapshot({ ...waitingOrder, smevMessageId: 'RESPONSE' })), true)
})

test('одинаковые снапшоты не дают изменений', () => {
  assert.deepEqual(diffSnapshots(toSnapshot(waitingOrder), toSnapshot(waitingOrder)), [])
})

test('изменённые поля перечисляются поимённо', () => {
  const previous = toSnapshot(waitingOrder)
  const current = toSnapshot({ ...waitingOrder, orderStatusId: 26, statuses: [{ title: 'Приглашение' }] })

  assert.deepEqual(diffSnapshots(previous, current).sort(), ['lastStatusTitle', 'orderStatusId', 'statusesCount'])
})
