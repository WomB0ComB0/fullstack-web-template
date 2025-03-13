# Makefile targets for development and testing
# Use make help for more info

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.PHONY: all
all: help

##@ Development

venv: ## Create a Python virtual environment
	$(info Creating Python 3 virtual environment...)
	poetry env use python
	poetry env info

activate: ## Activate the Python virtual environment
	$(info Activating virtual environment...)
	poetry env activate

install: ## Install Python dependencies
	$(info Installing dependencies...)
	poetry config virtualenvs.create false
	poetry install
	python -m pip install flake8 isort black

lint: ## Run the linter
	$(info Running linting...)
	python -m flake8 service --count --select=E9,F63,F7,F82 --show-source --statistics
	python -m flake8 service --count --max-complexity=10 --max-line-length=127 --statistics
	python -m pylint service --max-line-length=127

##@ Runtime

run: ## Run the service
	$(info Starting service...)
	honcho start
