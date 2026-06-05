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

import React from 'react'
import {useScope as createI18nScope} from '@canvas/i18n'
import {Alert} from '@instructure/ui-alerts'
import {Button} from '@instructure/ui-buttons'
import {Flex} from '@instructure/ui-flex'
import {Heading} from '@instructure/ui-heading'
import {Spinner} from '@instructure/ui-spinner'
import {Text} from '@instructure/ui-text'
import {View} from '@instructure/ui-view'
import {formatRegenerationCooldownLabel} from './formatRegenerationCooldown'
import {formatThreadSummary} from './formatThreadSummary'
import {useThreadSummary} from './useThreadSummary'
import {SummaryReportForm} from './SummaryReportForm'

const I18n = createI18nScope('discussion_topics_post')

export const ThreadSummaryBlock = () => {
  const {data, loading, error, regeneration, quotaExhaustedMessage, regenerate, regenerating} =
    useThreadSummary()

  if ((loading && !data) || !data || data.status === 'disabled') {
    return null
  }

  if (error) {
    return (
      <View as="div" margin="0 0 medium 0" data-testid="thread-summary-block">
        <Text color="danger" data-testid="thread-summary-error">
          {I18n.t('Unable to load thread summary.')}
        </Text>
      </View>
    )
  }

  const summaryText = formatThreadSummary(data.summary)
  const isGenerating = data.status === 'generating'
  const isCooldown =
    regeneration?.available === false && regeneration.reason === 'cooldown'
  const cooldownSeconds = regeneration?.retry_after_seconds
  const showRegenerateButton = !isGenerating

  const handleRegenerateClick = (
    event: React.MouseEvent<Element, MouseEvent> | React.KeyboardEvent<Element>,
  ) => {
    if (isCooldown) {
      event.preventDefault()
      return
    }
    void regenerate()
  }

  const renderRegenerateButton = () => {
    if (!showRegenerateButton) {
      return null
    }

    return (
      <Flex.Item>
        <Flex direction="column" alignItems="end">
          <Flex.Item>
            <Button
              color="secondary"
              size="small"
              data-testid="thread-summary-regenerate-button"
              aria-disabled={isCooldown ? 'true' : undefined}
              aria-label={I18n.t('Regenerate summary')}
              onClick={handleRegenerateClick}
              disabled={regenerating}
            >
              {I18n.t('Regenerate summary')}
            </Button>
          </Flex.Item>
          {isCooldown && cooldownSeconds != null && (
            <Flex.Item margin="x-small 0 0 0">
              <Text size="small" data-testid="thread-summary-regenerate-cooldown">
                {formatRegenerationCooldownLabel(cooldownSeconds)}
              </Text>
            </Flex.Item>
          )}
        </Flex>
      </Flex.Item>
    )
  }

  const disclosure = data.summary?.disclosure

  const renderSummaryText = () => {
    if (!summaryText) {
      return null
    }
    return (
      <Flex.Item margin="0 0 small 0">
        <Text data-testid="thread-summary-text">{summaryText}</Text>
      </Flex.Item>
    )
  }

  const renderDisclosure = () => {
    if (!disclosure) return null
    return (
      <Flex.Item margin="x-small 0 0 0">
        <Text size="small" color="secondary" data-testid="thread-summary-disclosure">
          {disclosure}
        </Text>
      </Flex.Item>
    )
  }

  const renderContent = () => {
    switch (data.status) {
      case 'generating':
        return (
          <div role="status" aria-live="polite" data-testid="thread-summary-generating">
            <Flex alignItems="center">
              <Flex.Item>
                <Spinner renderTitle={I18n.t('Generating thread summary')} size="x-small" />
              </Flex.Item>
              <Flex.Item margin="0 0 0 x-small">
                <Text>{I18n.t('Generating thread summary...')}</Text>
              </Flex.Item>
            </Flex>
          </div>
        )
      case 'rate_limited_empty':
        return (
          <Text data-testid="thread-summary-rate-limited-empty">
            {I18n.t('Summary unavailable; try again later.')}
          </Text>
        )
      case 'stale':
        return (
          <>
            <Flex.Item margin="0 0 small 0">
              <Alert
                variant="info"
                margin="0"
                hasShadow={false}
                data-testid="thread-summary-stale-alert"
              >
                {I18n.t(
                  'This summary may be outdated because the discussion has new activity.',
                )}
              </Alert>
            </Flex.Item>
            {renderSummaryText()}
            {renderDisclosure()}
          </>
        )
      case 'rate_limited_stale':
        return (
          <>
            {renderSummaryText()}
            {renderDisclosure()}
            <Flex.Item margin="small 0 0 0">
              <Text data-testid="thread-summary-rate-limited-stale">
                {I18n.t('Summary may be outdated; refresh limit reached.')}
              </Text>
            </Flex.Item>
          </>
        )
      case 'current':
        return (
          <>
            {renderSummaryText()}
            {renderDisclosure()}
          </>
        )
      default:
        return null
    }
  }

  return (
    <View
      as="div"
      margin="0 0 medium 0"
      padding="small"
      data-testid="thread-summary-block"
    >
      <Flex direction="column">
        {quotaExhaustedMessage && (
          <Flex.Item margin="0 0 small 0">
            <Alert
              variant="warning"
              margin="0"
              hasShadow={false}
              data-testid="thread-summary-quota-exhausted"
            >
              {quotaExhaustedMessage}
            </Alert>
          </Flex.Item>
        )}
        <Flex.Item margin="0 0 small 0">
          <Flex justifyItems="space-between" alignItems="start">
            <Flex.Item shouldGrow shouldShrink>
              <Heading level="h3">{I18n.t('Thread summary')}</Heading>
              <Text size="small" color="secondary">
                {I18n.t('AI-generated thread summary')}
              </Text>
            </Flex.Item>
            {renderRegenerateButton()}
          </Flex>
        </Flex.Item>
        {renderContent()}
        <Flex.Item margin="small 0 0 0">
          <SummaryReportForm />
        </Flex.Item>
      </Flex>
    </View>
  )
}
