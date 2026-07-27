#!/bin/bash

# Get the root directory
root_dir=$(git rev-parse --show-toplevel)
echo root_dir=$root_dir

# Auto install
if [ "$1" = "install" ]; then
	cd $root_dir/.git/hooks
	echo '#!/bin/bash' > pre-commit
	echo '$(git rev-parse --show-toplevel)/scripts/gitkeep.sh' >> pre-commit
	chmod +x pre-commit
	echo "done."
	cd -
	exit
fi

# Find all empty directories and create .gitkeep files
find "$root_dir" -type d -empty | while read -r dir; do
	# echo "$dir/.gitkeep"
	touch "$dir/.gitkeep"
	git add "$dir/.gitkeep"
done

