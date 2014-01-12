Rebol [
	Title: "Draem"
	Description: {
		This is the main module for the static website builder known as
		Draem.  Currently it implements loading of entries and the
		indexing of those entries.  The goal will be to also provide
		hooks for reusing the loader and then "munging" the entries
		to rewrite them using arbitrary meta-programming.
	}

	Home: https://github.com/hostilefork/draem
	License: 'mit

	Date: 20-Oct-2010
	Version: 3.0.4

	; Header conventions: http://www.rebol.org/one-click-submission-help.r
	File: %make-site.reb
	Type: 'dialect
	Level: 'intermediate

	Usage: {

	Current usage is just to run this script in the directory containing the
	subdirectory %entries/ and it will spit out a directory called %templates/

	}
]

do %common.reb

do %make-templates.reb
do %make-timeline.reb
do %make-atom-feed.reb			

draem: context [

	;-- Site configuration, defaults to none
	config: none

	set-config: func [
		{Do validation on the site configuration, and set it.}

		cfg [object!]
	] [
		assert [none? config]
		assert [all [
			;-- Required properties
			string? cfg/site-name
			url? cfg/site-url
			block? cfg/valid-categories
			dir? cfg/entries-dir
			dir? cfg/templates-dir

			;-- Required hooks
			function? :cfg/url-from-header

			;-- Optional hooks
			either in cfg 'check-header [
				function? :cfg/check-header
			] [
				true
			]
		]]

		config: cfg
	]


	;-- Block of entries sorted by reverse date, defaults to none
	entries: none

	set-entries: func [
		{Sets the entries block in this context, assumed valid.}

		ent [block!]
	] [
		assert [none? entries]
		entries: ent
	]


	;-- Indexing information, defaults to none
	indexes: none

	set-indexes: func [
		{Sets the index information in this context, assumed valid.}

		idx [object!]
	] [
		assert [none? indexes]
		indexes: idx
	]


	stage: function [
		{Log what stage we are in.}
		name [string!]
	] [
		print [{===} name {===}]
	]


	load-entries: function [
		{Recurse into the provided directory and load all the entries
		into a block, sorted reverse chronologically.}

		/recurse entries-dir [file!] entries [block!]
	] [
		unless recurse [
			stage "LOADING ENTRIES"

			; entries list sorted newest first, oldest last
			entries: copy []
			entries-dir: config/entries-dir
		]

		foreach file load entries-dir [
			either dir? file [
				subdir: rejoin [entries-dir file]
				print [{Recursing into:} subdir]
				load-entries/recurse subdir entries
			] [
				print [{Pre-processing:} file]

				data: load rejoin [entries-dir file]

				pos: data

				unless all [
					'Draem == first+ pos
					block? first pos
				] [
					throw make error! "Entry must start with Draem header"
				]

				header: make object! first+ pos

				unless all [
					in header 'date
					date? header/date
				] [
					throw make error! "Header requires valid date field"
				]

				unless all [
					in header 'slug
					file? header/slug
				] [
					throw make error! "Header requires a file! slug field"
				]

				unless all [
					in header 'title
					string? header/title
				] [
					throw make error! "Header requires a string! title field"
				]

				unless all [
					in header 'tags
					block? header/tags
					does [foreach tag header/tags [unless word? tag return false] true] 
				] [
					throw make error! "Header requires a tags block containing words"
				]

				unless all [
					in header 'category
					word? header/category
					find config/valid-categories header/category
				] [
					throw make error! "Header requires a legal category"
				]

				if in config 'check-header [
					config/check-header header
				]

				entry: make object! compose/only [
					header: (header)
					content: (copy pos)
				]

				append entries entry
			]
		]

		sort/compare entries func [a b] [a/header/date > b/header/date]

		unless recurse [
			set-entries entries
		]

		exit
	]


	build-indexes: function [
		{Build indexing information over the entries block.}
	] [
		stage "BUILDING INDEXES"

		indexes: object [
			; map from tags to list of entries with that tag
			tag-to-entries: make map! []

			; map from character to list of entries where they appear
			character-to-entries: make map! []

			; map from categories to list of entries in that category
			category-to-entries: make map! []

			; map from entry slug to the characters list appearing in it
			slug-to-characters: make map! []

			; map from entry slug to the entry itself
			slug-to-entry: make map! []
		]

		foreach entry entries [
			repend indexes/slug-to-entry [entry/header/slug entry]

			header: entry/header
			content: entry/content

			either select indexes/category-to-entries header/category [
				append select indexes/category-to-entries header/category entry
			] [
				append indexes/category-to-entries compose/deep copy/deep [(header/category) [(entry)]]
			]

			foreach tag header/tags [
				either select indexes/tag-to-entries tag [
					append select indexes/tag-to-entries tag entry
				] [

					append indexes/tag-to-entries compose/deep copy/deep [(tag) [(entry)]]
				]
			]

			; collect the characters from blocks beginning with set-word in the body
			characters: copy []
			repend indexes/slug-to-characters [entry/header/slug characters]

			pos: content
			while [not tail? pos] [
				line: first+ pos

				if all [
					block? line
					set-word? first line
					not find characters to word! first line
				] [
					append characters to word! first line
				]

				comment [
					if 'picture = first line [
						;;
						;; What to do?  Index or list these?  Scrape them?
						;;
					]
				]
			]

			foreach character characters [
				either select indexes/character-to-entries character [
					append select indexes/character-to-entries character entry
				] [
					append indexes/character-to-entries compose/deep copy/deep [(character) [(entry)]]
				]
			]
		]

		set-indexes indexes
	]


	make-site: function [] [

		;-- User must set the draem configuration before calling
		assert [object? config]

		err: catch [

			;-- Clients may have loaded the entries prior for analysis
			unless entries [load-entries]
			unless indexes [build-indexes]

			if exists? config/templates-dir [
				print [{Directory} config/templates-dir {currently exists.}]
				either "Y" = uppercase ask "Delete it [Y/N]?" [
					delete-dir config/templates-dir
				] [
					quit
				]
			]

			make-templates entries indexes config/templates-dir

			make-timeline entries rejoin [config/templates-dir %timeline.xml]

			make-atom-feed entries rejoin [config/templates-dir %atom.xml] 20

			none
		]

		if err [
			print form err
		]

		exit
	]
]