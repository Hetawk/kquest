import { describe, expect, it } from 'vitest';
import { importQuestionFile } from './importQuestions';

describe('question file import', () => {
	it('parses CSV answers and reads point and timer settings', async () => {
		const file = new File(
			[
				'question,option_a,option_b,option_c,option_d,correct_answer,points,time_limit_seconds\n' +
					'"Which is largest?","Jupiter","Mars","","","A",250,15'
			],
			'questions.csv',
			{ type: 'text/csv' }
		);

		const [question] = await importQuestionFile(file);

		expect(question?.prompt).toBe('Which is largest?');
		expect(question?.options.map((option) => option.text)).toEqual(['Jupiter', 'Mars']);
		expect(question?.correct_option_id).toBe(question?.options[0]?.id);
		expect(question?.points).toBe(250);
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
				'question,option_a,option_b,option_c,option_d,correct_answer,points,time_limit_seconds\n' +
					'"Which is largest?","Jupiter","Mars","","","A",,'
			],
			'questions.csv',
			{ type: 'text/csv' }
		);

		const [question] = await importQuestionFile(file);

		expect(question?.points).toBe(100);
		expect(question?.time_limit_seconds).toBe(30);
	});
});
