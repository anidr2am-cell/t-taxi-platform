# Blog language coverage

Checked on 2026-10-28. All 13 Korean source topics have Japanese, Simplified
Chinese and Russian articles, grouped by `translationKey`. Existing URLs are
preserved, including legacy golf slugs. There are 63 articles in total: Korean
13, English 11, Japanese 13, Chinese 13 and Russian 13.

## Reader paths

- `/blog/lang/zh/`: Simplified Chinese articles and Chinese booking.
- `/blog/lang/ja/`: Japanese articles and Japanese booking.
- `/blog/lang/ru/`: Russian articles with an explicit English booking transition.

The reservation app supports `ko`, `en`, `ja`, `zh` and `th`, not Russian.
Russian blog pages must use `lang=en` on all booking links. They do not promise
Russian-speaking support. No reservation application change is part of this work.

Airport arrival/return, booking preparation, fare checks and FAQ articles link
to one another in the same language. The three requested language indexes lead
with BKK arrivals, DMK arrivals and Pattaya return transfers, followed by booking
and FAQ guidance before golf planning. Readers can ask about Buddy Golf dates,
joining a round and TRider vehicle transfers together through the existing
company WhatsApp channel. Confirm available tee times and the complete itinerary
with the team. Budget guides still distinguish per-player golf costs from
per-vehicle transport costs.

## Facts and ongoing maintenance

Base airport fares and golf A/B/C transfer tables were checked against production
operating fare tables, read-only, on the date above. An exact address or optional
service can affect the final quote. Recheck prices before subsequent edits.

Unverified historical green fees, mileage benefits and the former TRounding BAND
contact were removed from the related guides in every existing translation.
The new BAND address remains unprovided; the existing company WhatsApp is the
shared consultation route approved by the owner on 2026-10-28. Existing URLs and translation keys
remain stable; do not rename them merely to update the display brand.

`blog:build` generates self canonicals, reciprocal language alternates, Article
and FAQ structured data, language indexes and sitemap entries. Translating a page
is not proof of search indexing, traffic or booking attribution. Language is not
customer nationality. Use consented source-linked records to evaluate bookings.

Run `npm run blog:build` and `npm run blog:test` before publishing changes. The
coverage tests verify each original's translations, local links, metadata,
Russian booking fallback and visible FAQ answers. Keep photo alt text and captions
localized; stock or reference vehicle pictures do not guarantee a luggage capacity.
