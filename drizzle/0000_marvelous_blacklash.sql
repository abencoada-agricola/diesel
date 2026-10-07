CREATE TABLE `fleets` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`type` text NOT NULL,
	`active` integer DEFAULT 1 NOT NULL
);
--> statement-breakpoint
CREATE TABLE `members` (
	`email` text PRIMARY KEY NOT NULL,
	`user_id` text,
	`role` text NOT NULL,
	`name` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `records` (
	`id` text PRIMARY KEY NOT NULL,
	`fleet` text NOT NULL,
	`date` text NOT NULL,
	`operator` text NOT NULL,
	`user_id` text NOT NULL,
	`engine` real,
	`elevator` real,
	`km` real,
	`start` real NOT NULL,
	`end` real NOT NULL,
	`liters` real NOT NULL,
	`signature` text NOT NULL,
	`notes` text NOT NULL,
	`created_at` text NOT NULL,
	`received_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `settings` (
	`id` text PRIMARY KEY NOT NULL,
	`value` text NOT NULL
);
