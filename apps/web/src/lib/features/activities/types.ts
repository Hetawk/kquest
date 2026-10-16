export type ChoiceOption = {
	id: string;
	text: string;
};

export type QuestionDraft = {
	prompt: string;
	options: ChoiceOption[];
	correct_option_id: string;
	points: number;
};

export type PlayQuestion = {
	id: string;
	prompt: string;
	points: number;
	options: ChoiceOption[];
};

export type PlayActivity = {
	id: string;
	title: string;
	share_code: string;
	questions: PlayQuestion[];
};

export type QuestionResult = {
	question_id: string;
	prompt: string;
	selected_option_id: string;
	correct_option_id: string;
	points_awarded: number;
	points_possible: number;
};

export type AttemptResult = {
	id: string;
	learner_name: string;
	score: number;
	max_score: number;
	results: QuestionResult[];
};

export type PublishedActivity = {
	title: string;
	version: number;
	share_code: string;
	play_path: string;
};
