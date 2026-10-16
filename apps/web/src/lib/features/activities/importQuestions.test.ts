import { readFile } from 'node:fs/promises';
import { describe, expect, it } from 'vitest';
import { importQuestionFile } from './importQuestions';

describe('question file import', () => {
	it('parses CSV answers and reads point, speed-bonus, and timer settings', async () => {
		const file = new File(
			[
				'question,option_a,option_b,option_c,option_d,correct_answer,points,speed_bonus_points,time_limit_seconds\n' +
					'"Which is largest?","Jupiter","Mars","","","A",250,350,15'
			],
			'questions.csv',
			{ type: 'text/csv' }
		);

		const [question] = await importQuestionFile(file);

		expect(question?.prompt).toBe('Which is largest?');
		expect(question?.options.map((option) => option.text)).toEqual(['Jupiter', 'Mars']);
		expect(question?.correct_option_id).toBe(question?.options[0]?.id);
		expect(question?.points).toBe(250);
		expect(question?.speed_bonus_points).toBe(350);
		expect(question?.time_limit_seconds).toBe(15);
	});

	it('rejects an answer column gap rather than changing answer letters', async () => {
		const file = new File(
			[
				'question,option_a,option_b,option_c,option_d,correct_answer\n' +
					'"Which is largest?","Jupiter","Mars","","Venus","D"'
			],
			'questions.csv',
			{ type: 'text/csv' }
		);

		await expect(importQuestionFile(file)).rejects.toThrow(
			'answer columns must be filled in order'
		);
	});

	it('defaults points and timers when those columns are blank', async () => {
		const file = new File(
			[
				'question,option_a,option_b,option_c,option_d,correct_answer,points,speed_bonus_points,time_limit_seconds\n' +
					'"Which is largest?","Jupiter","Mars","","","A",,,'
			],
			'questions.csv',
			{ type: 'text/csv' }
		);

		const [question] = await importQuestionFile(file);

		expect(question?.points).toBe(1);
		expect(question?.speed_bonus_points).toBe(100);
		expect(question?.time_limit_seconds).toBe(30);
	});

	it('imports all 40 questions from the NIA review CSV', async () => {
		const csv = await readFile(new URL('../../../../docs/questions.csv', import.meta.url), 'utf8');
		const file = new File([csv], 'questions.csv', { type: 'text/csv' });

		const questions = await importQuestionFile(file);
		const answersByLetter = ['A', 'B', 'C', 'D'].map(
			(letter) => (csv.match(new RegExp(`,"${letter}",1,100,30`, 'g')) ?? []).length
		);

		expect(questions).toHaveLength(40);
		expect(questions[0]?.prompt).toBe('When did NIA 2026 take place?');
		expect(questions[0]?.options[1]?.text).toBe('Tuesday 6th and Wednesday 7th October 2026');
		expect(questions[0]?.correct_option_id).toBe(questions[0]?.options[1]?.id);
		expect(questions[39]?.prompt).toBe('According to Psalm 127:3, how are children described?');
		expect(questions.every((question) => question.points === 1)).toBe(true);
		expect(questions.every((question) => question.speed_bonus_points === 100)).toBe(true);
		expect(questions.every((question) => question.time_limit_seconds === 30)).toBe(true);
		expect(answersByLetter).toEqual([7, 9, 12, 12]);
	});
});
