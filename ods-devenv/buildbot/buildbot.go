package main

import (
	"bufio"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/opendevstack/ods-core/ods-devenv/buildbot/utils"
)

func main() {
	fmt.Printf("Verifying build at %s.\n", time.Now().Format("2006-01-02T150405"))
	config, err := utils.ReadPackerRunControl()
	if err != nil || config == nil {
		log.Fatalf("Could not load runtime configuration: %v\n", err)
	}

	logPath := config["log_path"] + "/current"
	log.Println("logpath is " + logPath)

	logFile, err := os.Open(logPath)
	if err != nil {
		log.Fatalf("Could not open current log file: %v\n", err)
	}
	defer utils.CloseFile(logFile)

	log.Println("Scanning logfile " + logPath)
	amiBuildSuccessIndicator := "Installation completed."
	provappSuccessIndicator := "PASS: TestVerifyOdsProjectProvisionThruProvisionApi"
	quickstarterTestSuccessIndicator := "--- PASS: TestQuickstarter ("
	scanner := bufio.NewScanner(logFile)
	amiBuildSuccess := false
	provappTestSuccess := false
	quickstarterTestSuccess := false
	for scanner.Scan() {
		line := scanner.Text()
		if strings.Contains(line, amiBuildSuccessIndicator) {
			amiBuildSuccess = true
		} else if strings.Contains(line, provappSuccessIndicator) {
			provappTestSuccess = true
		} else if strings.Contains(line, quickstarterTestSuccessIndicator) {
			quickstarterTestSuccess = true
		}
	}

	// process build result
	buildResultPath := config["build_result_path"]
	// zip log file and copy it to download location
	err = utils.TarZip(config["log_path"]+"/current", config["build_result_path"]+"/current_log_master.tar.gz")
	if err != nil {
		log.Fatalf("Could not tar log file: %v\n", err)
	}

	if amiBuildSuccess {
		// write success svg to webserver dir
		log.Println("build success")
		utils.Copy(buildResultPath+"/success.svg", buildResultPath+"/buildStatus_master.svg")
	} else {
		// write failure svg to webserver dir
		log.Println("build failure")
		utils.Copy(buildResultPath+"/failure.svg", buildResultPath+"/buildStatus_master.svg")
	}

	if provappTestSuccess {
		log.Println("provapp tests PASS")
		utils.Copy(buildResultPath+"/success.svg", buildResultPath+"/provapptestsoutcome_master.svg")
	} else {
		log.Println("provapp tests FAIL")
		utils.Copy(buildResultPath+"/failure.svg", buildResultPath+"/provapptestsoutcome_master.svg")
	}

	if quickstarterTestSuccess {
		log.Println("quickstarter tests PASS")
		utils.Copy(buildResultPath+"/success.svg", buildResultPath+"/quickstartertestsoutcome_master.svg")
	} else {
		log.Println("quickstarter tests FAIL")
		utils.Copy(buildResultPath+"/failure.svg", buildResultPath+"/quickstartertestsoutcome_master.svg")
	}

}
