package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/BurntSushi/toml"
)

func main() {
	cfg := loadConfig()

	args := os.Args[1:]
	if len(args) == 0 {
		printUsage()
		os.Exit(1)
	}

	root := ""
	cmd := args[0]
	cmdArgs := args[1:]

	if cmd == "--help" || cmd == "-h" {
		printUsage()
		return
	}
	if cmd == "--version" || cmd == "-v" {
		fmt.Println("codedb-cli 2.0.0")
		return
	}

	if info, err := os.Stat(cmd); err == nil && info.IsDir() {
		root = cmd
		if len(cmdArgs) == 0 {
			printUsage()
			os.Exit(1)
		}
		cmd = cmdArgs[0]
		cmdArgs = cmdArgs[1:]
	}

	switch cmd {
	case "machine":
		if len(cmdArgs) == 0 {
			printMachineUsage()
			os.Exit(1)
		}
		handleMachine(cfg, cmdArgs)
	case "start":
		if root == "" {
			root = "."
		}
		root = absPath(root)
		ensureDaemon(cfg, root, cfg.DaemonPort)
		fmt.Fprintf(os.Stderr, "codedb running on :%d\n", cfg.DaemonPort)
	case "stop":
		stopAllDaemons()
	case "tree":
		root = resolveRoot(root)
		ensureDaemon(cfg, root, cfg.DaemonPort)
		resp := query(cfg.DaemonPort, "/explore/tree")
		fmt.Print(jsonStr(resp, "tree"))
	case "outline":
		requireArgs(cmdArgs, 1, "outline <path>")
		root = resolveRoot(root)
		ensureDaemon(cfg, root, cfg.DaemonPort)
		resp := query(cfg.DaemonPort, "/explore/outline?path="+url.QueryEscape(cmdArgs[0]))
		for _, sym := range jsonArr(resp, "symbols") {
			m := sym.(map[string]any)
			detail := ""
			if d, ok := m["detail"]; ok && d != nil {
				detail = fmt.Sprintf("%v", d)
			}
			fmt.Printf("L%.0f\t%s\t%s\t%s\n", m["line_start"], m["kind"], m["name"], detail)
		}
	case "find", "symbol":
		requireArgs(cmdArgs, 1, "find <symbol>")
		root = resolveRoot(root)
		ensureDaemon(cfg, root, cfg.DaemonPort)
		resp := query(cfg.DaemonPort, "/explore/symbol?name="+url.QueryEscape(cmdArgs[0]))
		for _, r := range jsonArr(resp, "results") {
			m := r.(map[string]any)
			detail := ""
			if d, ok := m["detail"]; ok && d != nil {
				detail = fmt.Sprintf("%v", d)
			}
			fmt.Printf("%s:%.0f\t%s\t%s\n", m["path"], m["line"], m["kind"], detail)
		}
	case "search":
		requireArgs(cmdArgs, 1, "search <query> [max]")
		root = resolveRoot(root)
		ensureDaemon(cfg, root, cfg.DaemonPort)
		max := "50"
		if len(cmdArgs) >= 2 {
			max = cmdArgs[1]
		}
		resp := query(cfg.DaemonPort, "/explore/search?q="+url.QueryEscape(cmdArgs[0])+"&max="+max)
		for _, r := range jsonArr(resp, "results") {
			m := r.(map[string]any)
			fmt.Printf("%s:%.0f\t%s\n", m["path"], m["line"], m["text"])
		}
	case "word":
		requireArgs(cmdArgs, 1, "word <identifier>")
		root = resolveRoot(root)
		ensureDaemon(cfg, root, cfg.DaemonPort)
		resp := query(cfg.DaemonPort, "/explore/word?q="+url.QueryEscape(cmdArgs[0]))
		for _, h := range jsonArr(resp, "hits") {
			m := h.(map[string]any)
			fmt.Printf("%s:%.0f\n", m["path"], m["line"])
		}
	case "hot":
		root = resolveRoot(root)
		ensureDaemon(cfg, root, cfg.DaemonPort)
		limit := "10"
		if len(cmdArgs) >= 1 {
			limit = cmdArgs[0]
		}
		resp := query(cfg.DaemonPort, "/explore/hot?limit="+limit)
		for _, f := range jsonArr(resp, "files") {
			fmt.Println(f)
		}
	case "deps":
		requireArgs(cmdArgs, 1, "deps <path>")
		root = resolveRoot(root)
		ensureDaemon(cfg, root, cfg.DaemonPort)
		resp := query(cfg.DaemonPort, "/explore/deps?path="+url.QueryEscape(cmdArgs[0]))
		for _, d := range jsonArr(resp, "imported_by") {
			fmt.Println(d)
		}
	case "read":
		requireArgs(cmdArgs, 1, "read <path> [start] [end]")
		root = resolveRoot(root)
		ensureDaemon(cfg, root, cfg.DaemonPort)
		resp := query(cfg.DaemonPort, "/file/read?path="+url.QueryEscape(cmdArgs[0]))
		content := jsonStr(resp, "content")
		if len(cmdArgs) >= 2 {
			lines := strings.Split(content, "\n")
			start, _ := strconv.Atoi(cmdArgs[1])
			end := len(lines)
			if len(cmdArgs) >= 3 {
				end, _ = strconv.Atoi(cmdArgs[2])
			}
			if start < 1 {
				start = 1
			}
			if end > len(lines) {
				end = len(lines)
			}
			for _, l := range lines[start-1 : end] {
				fmt.Println(l)
			}
		} else {
			fmt.Print(content)
		}
	case "status":
		root = resolveRoot(root)
		ensureDaemon(cfg, root, cfg.DaemonPort)
		health := query(cfg.DaemonPort, "/health")
		seq := query(cfg.DaemonPort, "/seq")
		fmt.Printf("health: %s\n", jsonStr(health, "status"))
		fmt.Printf("seq: %s\n", jsonStr(seq, "seq"))
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n", cmd)
		printUsage()
		os.Exit(1)
	}
}

// --- Machine commands ---

func handleMachine(cfg *Config, args []string) {
	switch args[0] {
	case "start":
		machineStart(cfg)
	case "stop":
		machineStop(cfg)
	case "status":
		machineStatus(cfg)
	case "roots":
		for _, r := range cfg.Roots {
			fmt.Println(expandHome(r))
		}
	case "search":
		if len(args) < 2 {
			fmt.Fprintln(os.Stderr, "usage: codedb-cli machine search <query> [max]")
			os.Exit(1)
		}
		max := "10"
		if len(args) >= 3 {
			max = args[2]
		}
		machineSearch(cfg, args[1], max)
	case "word":
		if len(args) < 2 {
			fmt.Fprintln(os.Stderr, "usage: codedb-cli machine word <identifier>")
			os.Exit(1)
		}
		machineWord(cfg, args[1])
	case "find":
		if len(args) < 2 {
			fmt.Fprintln(os.Stderr, "usage: codedb-cli machine find <symbol>")
			os.Exit(1)
		}
		machineFind(cfg, args[1])
	default:
		printMachineUsage()
		os.Exit(1)
	}
}

func machineStart(cfg *Config) {
	stateDir := stateDirectory()
	os.MkdirAll(stateDir, 0755)

	port := cfg.PortStart
	for _, r := range cfg.Roots {
		root := expandHome(r)
		if !isDir(root) {
			fmt.Fprintf(os.Stderr, "skip %s (not found)\n", root)
			continue
		}
		root = absPath(root)
		ensureDaemon(cfg, root, port)
		writePortFile(stateDir, root, port)
		fmt.Fprintf(os.Stderr, "%-50s :%d\n", root, port)
		port++
	}
}

func machineStop(cfg *Config) {
	stateDir := stateDirectory()
	entries, err := os.ReadDir(stateDir)
	if err != nil {
		return
	}
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".pid") {
			pidBytes, _ := os.ReadFile(filepath.Join(stateDir, e.Name()))
			pid := strings.TrimSpace(string(pidBytes))
			if pid != "" {
				exec.Command("kill", pid).Run()
			}
			os.Remove(filepath.Join(stateDir, e.Name()))
		}
		if strings.HasSuffix(e.Name(), ".port") {
			os.Remove(filepath.Join(stateDir, e.Name()))
		}
	}
	fmt.Fprintln(os.Stderr, "all machine daemons stopped")
}

func machineStatus(cfg *Config) {
	stateDir := stateDirectory()
	for _, r := range cfg.Roots {
		root := expandHome(r)
		if !isDir(root) {
			continue
		}
		root = absPath(root)
		port := readPortFile(stateDir, root)
		status := "stopped"
		if port > 0 && pingDaemon(port) {
			status = fmt.Sprintf("running :%d", port)
		}
		fmt.Printf("%-50s %s\n", root, status)
	}
}

type searchResult struct {
	Root    string
	Results []string
	Elapsed time.Duration
}

func machineSearch(cfg *Config, q string, max string) {
	stateDir := stateDirectory()
	var wg sync.WaitGroup
	results := make(chan searchResult, len(cfg.Roots))

	t0 := time.Now()
	for _, r := range cfg.Roots {
		root := expandHome(r)
		if !isDir(root) {
			continue
		}
		root = absPath(root)
		port := readPortFile(stateDir, root)

		wg.Add(1)
		go func(root string, port int) {
			defer wg.Done()
			rt0 := time.Now()
			var lines []string

			if port > 0 && pingDaemon(port) {
				resp := queryPort(port, "/explore/search?q="+url.QueryEscape(q)+"&max="+max)
				if resp != nil {
					for _, r := range jsonArr(resp, "results") {
						m := r.(map[string]any)
						lines = append(lines, fmt.Sprintf("%s:%.0f\t%s", m["path"], m["line"], m["text"]))
					}
				}
			} else {
				maxInt, _ := strconv.Atoi(max)
				if maxInt == 0 {
					maxInt = 10
				}
				lines = rgSearch(root, q, maxInt)
			}
			results <- searchResult{Root: root, Results: lines, Elapsed: time.Since(rt0)}
		}(root, port)
	}

	go func() { wg.Wait(); close(results) }()

	any := false
	for sr := range results {
		if len(sr.Results) == 0 {
			continue
		}
		any = true
		fmt.Printf("==> %s <==\n", sr.Root)
		fmt.Fprintf(os.Stderr, "%s: %s\n", sr.Root, sr.Elapsed.Round(time.Microsecond))
		for _, l := range sr.Results {
			fmt.Println(l)
		}
		fmt.Println()
	}
	if !any {
		fmt.Printf("no matches for: %s\n", q)
	}
	fmt.Fprintf(os.Stderr, "total: %s\n", time.Since(t0).Round(time.Microsecond))
}

func machineWord(cfg *Config, word string) {
	stateDir := stateDirectory()
	var wg sync.WaitGroup
	results := make(chan searchResult, len(cfg.Roots))

	t0 := time.Now()
	for _, r := range cfg.Roots {
		root := expandHome(r)
		if !isDir(root) {
			continue
		}
		root = absPath(root)
		port := readPortFile(stateDir, root)

		wg.Add(1)
		go func(root string, port int) {
			defer wg.Done()
			rt0 := time.Now()
			var lines []string

			if port > 0 && pingDaemon(port) {
				resp := queryPort(port, "/explore/word?q="+url.QueryEscape(word))
				if resp != nil {
					for _, h := range jsonArr(resp, "hits") {
						m := h.(map[string]any)
						lines = append(lines, fmt.Sprintf("%s:%.0f", m["path"], m["line"]))
					}
				}
			} else {
				lines = rgWord(root, word, 20)
			}
			results <- searchResult{Root: root, Results: lines, Elapsed: time.Since(rt0)}
		}(root, port)
	}

	go func() { wg.Wait(); close(results) }()

	for sr := range results {
		if len(sr.Results) == 0 {
			continue
		}
		fmt.Printf("==> %s <==\n", sr.Root)
		fmt.Fprintf(os.Stderr, "%s: %s\n", sr.Root, sr.Elapsed.Round(time.Microsecond))
		for _, l := range sr.Results {
			fmt.Println(l)
		}
		fmt.Println()
	}
	fmt.Fprintf(os.Stderr, "total: %s\n", time.Since(t0).Round(time.Microsecond))
}

func machineFind(cfg *Config, symbol string) {
	stateDir := stateDirectory()
	var wg sync.WaitGroup
	results := make(chan searchResult, len(cfg.Roots))

	t0 := time.Now()
	for _, r := range cfg.Roots {
		root := expandHome(r)
		if !isDir(root) {
			continue
		}
		root = absPath(root)
		port := readPortFile(stateDir, root)

		wg.Add(1)
		go func(root string, port int) {
			defer wg.Done()
			rt0 := time.Now()
			var lines []string

			if port > 0 && pingDaemon(port) {
				resp := queryPort(port, "/explore/symbol?name="+url.QueryEscape(symbol))
				if resp != nil {
					for _, r := range jsonArr(resp, "results") {
						m := r.(map[string]any)
						detail := ""
						if d, ok := m["detail"]; ok && d != nil {
							detail = fmt.Sprintf("%v", d)
						}
						lines = append(lines, fmt.Sprintf("%s:%.0f\t%s\t%s", m["path"], m["line"], m["kind"], detail))
					}
				}
			}
			results <- searchResult{Root: root, Results: lines, Elapsed: time.Since(rt0)}
		}(root, port)
	}

	go func() { wg.Wait(); close(results) }()

	for sr := range results {
		if len(sr.Results) == 0 {
			continue
		}
		fmt.Printf("==> %s <==\n", sr.Root)
		fmt.Fprintf(os.Stderr, "%s: %s\n", sr.Root, sr.Elapsed.Round(time.Microsecond))
		for _, l := range sr.Results {
			fmt.Println(l)
		}
		fmt.Println()
	}
	fmt.Fprintf(os.Stderr, "total: %s\n", time.Since(t0).Round(time.Microsecond))
}

// --- Daemon management ---

func ensureDaemon(cfg *Config, root string, port int) {
	if pingDaemon(port) {
		return
	}
	binary := cfg.Binary
	fmt.Fprintf(os.Stderr, "starting codedb %s on :%d ...\n", root, port)
	cmd := exec.Command(binary, root, "--port", strconv.Itoa(port), "serve")
	cmd.Stdout = nil
	cmd.Stderr = nil
	cmd.Start()

	stateDir := stateDirectory()
	os.MkdirAll(stateDir, 0755)
	if cmd.Process != nil {
		pidFile := filepath.Join(stateDir, portKey(root)+".pid")
		os.WriteFile(pidFile, []byte(strconv.Itoa(cmd.Process.Pid)), 0644)
		writePortFile(stateDir, root, port)
		// Detach so daemon survives CLI exit
		cmd.Process.Release()
	}

	for i := 0; i < 200; i++ {
		time.Sleep(50 * time.Millisecond)
		if pingDaemon(port) {
			return
		}
	}
	fmt.Fprintf(os.Stderr, "warning: codedb on :%d did not become ready\n", port)
}

func pingDaemon(port int) bool {
	client := &http.Client{Timeout: 200 * time.Millisecond}
	resp, err := client.Get(fmt.Sprintf("http://localhost:%d/health", port))
	if err != nil {
		return false
	}
	resp.Body.Close()
	return resp.StatusCode == 200
}

func stopAllDaemons() {
	// Kill tracked daemons by PID first, fall back to pkill
	stateDir := stateDirectory()
	killed := false
	if entries, err := os.ReadDir(stateDir); err == nil {
		for _, e := range entries {
			if strings.HasSuffix(e.Name(), ".pid") {
				pidBytes, _ := os.ReadFile(filepath.Join(stateDir, e.Name()))
				pid := strings.TrimSpace(string(pidBytes))
				if pid != "" {
					exec.Command("kill", pid).Run()
					killed = true
				}
				os.Remove(filepath.Join(stateDir, e.Name()))
			}
			if strings.HasSuffix(e.Name(), ".port") || strings.HasSuffix(e.Name(), ".root") {
				os.Remove(filepath.Join(stateDir, e.Name()))
			}
		}
	}
	if !killed {
		exec.Command("pkill", "-xf", "codedb .* serve").Run()
	}
	fmt.Fprintln(os.Stderr, "codedb stopped")
}

// --- HTTP helpers ---

var httpClient = &http.Client{Timeout: 5 * time.Second}

func query(port int, path string) map[string]any {
	return queryPort(port, path)
}

func queryPort(port int, path string) map[string]any {
	resp, err := httpClient.Get(fmt.Sprintf("http://localhost:%d%s", port, path))
	if err != nil {
		return nil
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	var result map[string]any
	json.Unmarshal(body, &result)
	return result
}

func jsonStr(m map[string]any, key string) string {
	if m == nil {
		return ""
	}
	v, ok := m[key]
	if !ok || v == nil {
		return ""
	}
	switch t := v.(type) {
	case string:
		return t
	case float64:
		return strconv.FormatFloat(t, 'f', -1, 64)
	default:
		return fmt.Sprintf("%v", v)
	}
}

func jsonArr(m map[string]any, key string) []any {
	if m == nil {
		return nil
	}
	v, ok := m[key]
	if !ok || v == nil {
		return nil
	}
	arr, ok := v.([]any)
	if !ok {
		return nil
	}
	return arr
}

// --- rg fallback ---

func rgSearch(root, q string, max int) []string {
	cmd := exec.Command("rg", "-n", "--no-messages", "--hidden",
		"--glob", "*.{zig,c,h,cpp,hpp,py,js,jsx,ts,tsx,rs,go,php,rb,md,json,yaml,yml}",
		"-g", "!**/.git/**", "-g", "!**/node_modules/**", "-g", "!**/target/**",
		"-g", "!**/.zig-cache/**", "-g", "!**/zig-out/**", "-g", "!**/dist/**",
		"-g", "!**/build/**", "-g", "!**/__pycache__/**", "-g", "!**/.venv/**",
		"-F", "--", q, root)
	out, _ := cmd.Output()
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	if len(lines) == 1 && lines[0] == "" {
		return nil
	}
	if len(lines) > max {
		lines = lines[:max]
	}
	return lines
}

func rgWord(root, word string, max int) []string {
	cmd := exec.Command("rg", "-n", "--no-messages", "--hidden", "-w",
		"--glob", "*.{zig,c,h,cpp,hpp,py,js,jsx,ts,tsx,rs,go,php,rb,md,json,yaml,yml}",
		"-g", "!**/.git/**", "-g", "!**/node_modules/**", "-g", "!**/target/**",
		"-F", "--", word, root)
	out, _ := cmd.Output()
	raw := strings.Split(strings.TrimSpace(string(out)), "\n")
	if len(raw) == 1 && raw[0] == "" {
		return nil
	}
	// Strip to path:line (match daemon word output format)
	var lines []string
	for _, l := range raw {
		if len(lines) >= max {
			break
		}
		// rg output is path:line:text — find second colon and truncate
		first := strings.IndexByte(l, ':')
		if first < 0 {
			continue
		}
		second := strings.IndexByte(l[first+1:], ':')
		if second >= 0 {
			lines = append(lines, l[:first+1+second])
		} else {
			lines = append(lines, l)
		}
	}
	return lines
}

// --- Config ---

type Config struct {
	Binary     string   `toml:"binary"`
	DaemonPort int      `toml:"daemon_port"`
	PortStart  int      `toml:"port_start"`
	Roots      []string `toml:"roots"`
}

func defaultConfig() *Config {
	return &Config{
		Binary:     "codedb",
		DaemonPort: 7719,
		PortStart:  7720,
		Roots:      []string{},
	}
}

func loadConfig() *Config {
	cfg := defaultConfig()
	configDir := configDirectory()
	configFile := filepath.Join(configDir, "config.toml")

	if _, err := os.Stat(configFile); os.IsNotExist(err) {
		os.MkdirAll(configDir, 0755)
		writeDefaultConfig(configFile)
		fmt.Fprintf(os.Stderr, "created %s — edit to configure your roots\n", configFile)
	}

	if _, err := toml.DecodeFile(configFile, cfg); err != nil {
		fmt.Fprintf(os.Stderr, "warning: config parse error: %v\n", err)
	}
	return cfg
}

func configDirectory() string {
	if xdg := os.Getenv("XDG_CONFIG_HOME"); xdg != "" {
		return filepath.Join(xdg, "codedb-cli")
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "codedb-cli")
}

func stateDirectory() string {
	if xdg := os.Getenv("XDG_STATE_HOME"); xdg != "" {
		return filepath.Join(xdg, "codedb-cli")
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".local", "state", "codedb-cli")
}

func writeDefaultConfig(path string) {
	content := `# codedb-cli configuration
# See: codedb-cli --help

# Path to codedb binary
binary = "codedb"

# Default port for single-root daemon
daemon_port = 7719

# Starting port for machine-wide daemons (one per root, incrementing)
port_start = 7720

# Machine-wide roots — each gets its own daemon for microsecond search
# Edit these to match your machine layout
roots = [
]
`
	os.WriteFile(path, []byte(content), 0644)
}

// --- Path/file helpers ---

func expandHome(path string) string {
	if strings.HasPrefix(path, "~/") {
		home, _ := os.UserHomeDir()
		return filepath.Join(home, path[2:])
	}
	return path
}

func absPath(path string) string {
	abs, err := filepath.Abs(path)
	if err != nil {
		return path
	}
	return abs
}

func resolveRoot(root string) string {
	if root == "" {
		root = "."
	}
	return absPath(root)
}

func isDir(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}

func portKey(root string) string {
	h := uint32(0)
	for _, c := range root {
		h = h*31 + uint32(c)
	}
	return fmt.Sprintf("%08x", h)
}

func writePortFile(stateDir, root string, port int) {
	key := portKey(root)
	os.WriteFile(filepath.Join(stateDir, key+".port"), []byte(strconv.Itoa(port)), 0644)
	os.WriteFile(filepath.Join(stateDir, key+".root"), []byte(root), 0644)
}

func readPortFile(stateDir, root string) int {
	key := portKey(root)
	data, err := os.ReadFile(filepath.Join(stateDir, key+".port"))
	if err != nil {
		return 0
	}
	port, _ := strconv.Atoi(strings.TrimSpace(string(data)))
	return port
}

func requireArgs(args []string, n int, usage string) {
	if len(args) < n {
		fmt.Fprintf(os.Stderr, "usage: codedb-cli %s\n", usage)
		os.Exit(1)
	}
}

// --- Usage ---

func printUsage() {
	fmt.Fprint(os.Stderr, `codedb-cli — fast CLI for codedb daemon

usage: codedb-cli [root] <command> [args...]

commands:
  tree                          file tree with symbol counts
  outline <path>                symbols in a file
  find    <symbol>              find symbol definitions
  search  <query> [max]         trigram full-text search
  word    <identifier>          O(1) inverted index lookup
  hot     [limit]               recently modified files
  deps    <path>                reverse dependency graph
  read    <path> [start] [end]  read file content (line range)
  status                        index status / health
  start   [root]                start the daemon
  stop                          stop all codedb daemons
  machine <subcommand>          machine-wide search across all roots

machine:
  machine start                 start a daemon per root
  machine stop                  stop all machine daemons
  machine status                show daemon status per root
  machine roots                 list configured roots
  machine search <query> [max]  parallel search across all roots
  machine word <identifier>     parallel word lookup across all roots
  machine find <symbol>         parallel symbol find across all roots

config: ~/.config/codedb-cli/config.toml

flags:
  --help, -h                    show this help
  --version, -v                 show version
`)
}

func printMachineUsage() {
	fmt.Fprint(os.Stderr, `machine commands:
  machine start                 start a daemon per root
  machine stop                  stop all machine daemons
  machine status                show daemon status per root
  machine roots                 list configured roots
  machine search <query> [max]  parallel search across all roots
  machine word <identifier>     parallel word lookup across all roots
  machine find <symbol>         parallel symbol find across all roots
`)
}
