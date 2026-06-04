/*
 * Copyright (C) 2026 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 *
 * Canvas is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Affero General Public License as published by the Free
 * Software Foundation, version 3 of the License.
 *
 * Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Affero General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import React, {useCallback, useEffect, useState} from 'react'
import {useScope as createI18nScope} from '@canvas/i18n'
import {Alert} from '@instructure/ui-alerts'
import {Button} from '@instructure/ui-buttons'
import {Flex} from '@instructure/ui-flex'
import {Heading} from '@instructure/ui-heading'
import {Link} from '@instructure/ui-link'
import {Spinner} from '@instructure/ui-spinner'
import {Text} from '@instructure/ui-text'
import {View} from '@instructure/ui-view'
import doFetchApi from '@canvas/do-fetch-api-effect'

const I18n = createI18nScope('discussion_topics_post')

const MAX_QUESTION_LENGTH = 200

export interface OpenQuestion {
  question_id: number
  thread_id: number
  thread_title: string
  question_text: string
  created_at: string
  deep_link: string
}

declare const ENV: {
  COURSE_ID?: string | number
  discussion_thread_summarizer_enabled?: boolean
  permissions?: {moderate?: boolean}
}

function relativeAge(isoString: string): string {
  const diffMs = Date.now() - new Date(isoString).getTime()
  const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24))
  if (diffDays === 0) return I18n.t('Today')
  if (diffDays === 1) return I18n.t('1 day ago')
  return I18n.t('%{count} days ago', {count: diffDays})
}

function truncateQuestion(text: string): string {
  if (text.length <= MAX_QUESTION_LENGTH) return text
  return text.slice(0, MAX_QUESTION_LENGTH) + '…'
}

function buildOpenQuestionsPath(): string {
  return `/api/v1/courses/${ENV.COURSE_ID}/discussion_topics/open_questions`
}

function buildDismissPath(questionId: number): string {
  return `/api/v1/courses/${ENV.COURSE_ID}/discussion_questions/${questionId}/dismiss`
}

export const OpenQuestionsDigest = () => {
  const flagEnabled = ENV.discussion_thread_summarizer_enabled
  const isModerator = ENV.permissions?.moderate

  const [questions, setQuestions] = useState<OpenQuestion[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<Error | null>(null)
  const [dismissErrors, setDismissErrors] = useState<Record<number, string>>({})
  const [liveMessage, setLiveMessage] = useState<string>('')

  const fetchQuestions = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const {json} = await doFetchApi<OpenQuestion[]>({
        path: buildOpenQuestionsPath(),
        method: 'GET',
      })
      setQuestions(json ?? [])
    } catch (err) {
      setError(err instanceof Error ? err : new Error(String(err)))
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    if (!flagEnabled || !isModerator) return
    void fetchQuestions()
  }, [flagEnabled, isModerator, fetchQuestions])

  const handleDismiss = useCallback(
    async (question: OpenQuestion) => {
      // Optimistic remove
      setQuestions(prev => prev.filter(q => q.question_id !== question.question_id))
      setDismissErrors(prev => {
        const next = {...prev}
        delete next[question.question_id]
        return next
      })

      try {
        await doFetchApi({
          path: buildDismissPath(question.question_id),
          method: 'POST',
        })
        setLiveMessage(I18n.t('Question dismissed.'))
      } catch {
        // Restore on failure: re-insert sorted oldest-first by created_at
        setQuestions(prev =>
          [...prev, question].sort(
            (a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime(),
          ),
        )
        setDismissErrors(prev => ({
          ...prev,
          [question.question_id]: I18n.t('Failed to dismiss. Please try again.'),
        }))
      }
    },
    [],
  )

  if (!flagEnabled || !isModerator) {
    return null
  }

  return (
    <View as="div" margin="medium 0" padding="small" data-testid="open-questions-digest">
      <Heading level="h2" data-testid="open-questions-heading">
        {I18n.t('Open Questions')}
      </Heading>
      <div
        aria-live="polite"
        aria-atomic="true"
        data-testid="open-questions-live-region"
        style={{position: 'absolute', left: '-9999px'}}
      >
        {liveMessage}
      </div>

      {loading && (
        <Flex alignItems="center" margin="small 0" data-testid="open-questions-loading">
          <Flex.Item>
            <Spinner renderTitle={I18n.t('Loading open questions')} size="x-small" />
          </Flex.Item>
          <Flex.Item margin="0 0 0 x-small">
            <Text>{I18n.t('Loading open questions...')}</Text>
          </Flex.Item>
        </Flex>
      )}

      {!loading && error && (
        <Alert variant="error" data-testid="open-questions-error">
          {I18n.t('Unable to load open questions.')}
        </Alert>
      )}

      {!loading && !error && questions.length === 0 && (
        <Text data-testid="open-questions-empty">
          {I18n.t('No open questions at this time.')}
        </Text>
      )}

      {!loading && !error && questions.length > 0 && (
        <div
          role="list"
          aria-label={I18n.t('Open questions, %{count} items', {count: questions.length})}
          data-testid="open-questions-list"
        >
          {questions.map(question => (
            <View
              key={question.question_id}
              as="div"
              role="listitem"
              margin="small 0"
              padding="x-small"
              data-testid={`open-question-row-${question.question_id}`}
            >
              <Flex justifyItems="space-between" alignItems="start">
                <Flex.Item shouldGrow shouldShrink>
                  <Text
                    data-testid={`open-question-text-${question.question_id}`}
                    wrap="break-word"
                  >
                    {truncateQuestion(question.question_text)}
                  </Text>
                  <Flex margin="x-small 0 0 0">
                    <Flex.Item margin="0 small 0 0">
                      <Text
                        size="small"
                        color="secondary"
                        data-testid={`open-question-thread-${question.question_id}`}
                      >
                        {question.thread_title}
                      </Text>
                    </Flex.Item>
                    <Flex.Item margin="0 small 0 0">
                      <Text
                        size="small"
                        color="secondary"
                        data-testid={`open-question-age-${question.question_id}`}
                      >
                        {relativeAge(question.created_at)}
                      </Text>
                    </Flex.Item>
                    <Flex.Item>
                      <Link
                        href={question.deep_link}
                        data-testid={`open-question-link-${question.question_id}`}
                      >
                        {I18n.t('Go to thread')}
                      </Link>
                    </Flex.Item>
                  </Flex>
                  {dismissErrors[question.question_id] && (
                    <Text
                      color="danger"
                      data-testid={`open-question-dismiss-error-${question.question_id}`}
                    >
                      {dismissErrors[question.question_id]}
                    </Text>
                  )}
                </Flex.Item>
                <Flex.Item>
                  <Button
                    size="small"
                    color="secondary"
                    onClick={() => void handleDismiss(question)}
                    data-testid={`open-question-dismiss-${question.question_id}`}
                    aria-label={I18n.t('Dismiss question from thread %{title}', {
                      title: question.thread_title,
                    })}
                  >
                    {I18n.t('Dismiss')}
                  </Button>
                </Flex.Item>
              </Flex>
            </View>
          ))}
        </div>
      )}
    </View>
  )
}
