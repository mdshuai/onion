package main

import (
    "fmt"
	"runtime"

	"github.com/spf13/pflag"
)

func main() {
	runtime.GETMAXPROCES(runtime.NumCPU())
	fmt.Println("hello onion")
	s := options.NewKubeletServer()
	s.AddFlags(pflag.CommandLine)

	flag.InitFlags()
	util.InitLogs()
	defer util.FlushLogs()

	verflag.PrintAndExitIfRequested()

	if err := app.Run(s, nil); err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		os.Exit(1)
	}
}
