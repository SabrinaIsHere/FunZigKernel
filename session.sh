# https://www.geeksforgeeks.org/linux-unix/how-to-create-tmux-session-with-a-script/

SESSION="ZigKernel"
PROJECT="~/Projects/Zig/FunZigKernel"

# Check if the session already exists
if ! tmux has-session -t $SESSION 2>/dev/null; then
    tmux new-session -d -n "Code" -c "$PROJECT" -s "$SESSION"
    tmux send-keys -t "$SESSION:0" "cd $PROJECT; nvim src/main.zig" C-m
    
	tmux new-window -n "Build" -t "$SESSION"
    tmux send-keys -t "$SESSION:1" "ls" C-m
    
	tmux new-window -n "Notes" -t "$SESSION"
    tmux send-keys -t "$SESSION:2" "nvim notes/architecture.md" C-m
fi

tmux attach-session -t "$SESSION_NAME:0"
