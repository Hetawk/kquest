export type ChoiceOption = {
	id: string;
	text: string;
};

export type QuestionDraft = {
	prompt: string;
	options: ChoiceOption[];
	correct_option_id: string;
	points: number;
	time_limit_seconds: number;
};

export type PlayQuestion = {
	id: string;
	prompt: string;
	points: number;
	time_limit_seconds: number;
	options: ChoiceOption[];
};

export type PlayActivity = {
	id: string;
	title: string;
	share_code: string;
	cover_image_url: string | null;
	questions: PlayQuestion[];
};

export type QuestionResult = {
	question_id: string;
	prompt: string;
	selected_option_id: string | null;
	correct_option_id: string;
	timed_out: boolean;
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

export type PlaySession = {
	id: string;
	question_index: number;
	time_limit_seconds: number;
	time_remaining_seconds: number;
	question_started_at: string;
	server_time: string;
};

export type PlaySessionProgress =
	| {
			complete: false;
			is_correct: boolean;
			timed_out: boolean;
			question_index: number;
			time_limit_seconds: number;
			question_started_at: string;
			server_time: string;
	  }
	| {
			complete: true;
			is_correct: boolean;
			timed_out: boolean;
			attempt: AttemptResult;
	  };

export type PublishedActivity = {
	title: string;
	version: number;
	share_code: string;
	play_path: string;
};
