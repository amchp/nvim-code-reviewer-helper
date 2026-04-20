test:
	nvim --headless --clean -u tests/minimal_init.lua -c "lua require('code_review_helper_test.runner').run()" -c "qa!"

pr_ready: test
