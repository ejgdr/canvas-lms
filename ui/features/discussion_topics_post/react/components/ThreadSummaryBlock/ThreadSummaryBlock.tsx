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
import {Flex} from '@instructure/ui-flex'
import {Heading} from '@instructure/ui-heading'
import {Spinner} from '@instructure/ui-spinner'
import {Text} from '@instructure/ui-text'
import {View} from '@instructure/ui-view'
import {formatThreadSummary} from './formatThreadSummary'
import {useThreadSummary} from './useThreadSummary'

const I18n = createI18nScope('discussion_topics_post')

export const ThreadSummaryBlock = () => {
  const {data, loading, error} = useThreadSummary()

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
          </>
        )
      case 'rate_limited_stale':
        return (
          <>
            {renderSummaryText()}
            <Flex.Item margin="small 0 0 0">
              <Text data-testid="thread-summary-rate-limited-stale">
                {I18n.t('Summary may be outdated; refresh limit reached.')}
              </Text>
            </Flex.Item>
          </>
        )
      case 'current':
        return renderSummaryText()
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
        <Flex.Item margin="0 0 small 0">
          <Heading level="h3">{I18n.t('Thread summary')}</Heading>
          <Text size="small" color="secondary">
            {I18n.t('AI-generated thread summary')}
          </Text>
        </Flex.Item>
        {renderContent()}
      </Flex>
    </View>
  )
}
