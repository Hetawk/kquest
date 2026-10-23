import { describe, expect, it } from 'vitest';
import { buildGameRoomResultsCsv } from './resultsCsv';
import type { GameRoomReport } from './types';

describe('buildGameRoomResultsCsv', () => {
	it('exports answer details and protects spreadsheet cells from formulas', () => {
		const report: GameRoomReport = {
			room_code: 'ABCD23',
			title: 'Quest',
			completed_at: null,
			participant_count: 1,
			question_count: 1,
			average_score: 100,
			max_score: 100,
			accuracy_percent: 100,
			questions: [
				{
					id: 'question-id',
					number: 1,
					prompt: '=HYPERLINK("https://example.test")',
					points_possible: 100,
					correct_answer: 'Mars, "the red planet"',
					participant_count: 1,
					answered_count: 1,
					correct_count: 1,
					missed_count: 0,
					timed_out_count: 0,
					accuracy_percent: 100
				}
			],
			participants: [
				{
					learner_name: '+CMD()',
					avatar_id: 'panda',
					rank: 1,
					score: 100,
					max_score: 100,
					questions: [
						{
							question_id: 'question-id',
							selected_answer: 'Mars, "the red planet"',
							correct_answer: 'Mars, "the red planet"',
							is_correct: true,
							timed_out: false,
							points_awarded: 100,
							points_possible: 100,
							response_time_ms: 1200
						}
					]
				}
			]
		};

		const csv = buildGameRoomResultsCsv(report);
		expect(csv.startsWith('\uFEFF')).toBe(true);
		expect(csv).toContain(`"'=HYPERLINK(""https://example.test"")"`);
		expect(csv).toContain(`"'+CMD()"`);
		expect(csv).toContain(`"Mars, ""the red planet"""`);
		expect(csv).toContain('"Correct","100","100","1200"');
	});
});
