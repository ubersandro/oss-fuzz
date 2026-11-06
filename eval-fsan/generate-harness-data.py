import os
# open projects.txt to get projects 
projects_data = []
with open("/tmp/ciao", "r") as f:
    for line in f:
        name, count, language = line.strip().split(":")
        projects_data.append((name, language))
        
N = os.environ.get("N", 15)
# get N with C and N with C++
C_TARGETS = [name for name, language in projects_data if language == "c"]
CPP_TARGETS = [name for name, language in projects_data if language == "c++"]
print(f"C_TARGETS: {(C_TARGETS)},\nCPP_TARGETS: {(CPP_TARGETS)}")
print("number of C targets: {}, number of C++ targets: {}".format(len(C_TARGETS), len(CPP_TARGETS)))
TARGETS = C_TARGETS[:N] + CPP_TARGETS[:N]
# import time
# time.sleep(10)
BASE_URL="https://introspector.oss-fuzz.com/project-profile?project=" # + PROJ_NAME

import requests 
from bs4 import BeautifulSoup
# for each of the tested apps, report data on harnesses 

count = 0
for target in TARGETS:
    url = BASE_URL + target
    response = requests.get(url)
    # find "Fuzzer count" in table profile__table
    if response.status_code == 200:
        print("PROJECT: {}, LANGUAGE: {}".format(target, "C" if target in C_TARGETS else "C++"))

        soup = BeautifulSoup(response.text, 'html.parser')
        project_profile_wrapper = soup.find('div', class_='project__profile-wrapper') #          <div class="project__profile-wrapper">
        tables = project_profile_wrapper.find_all('table')

        rows_t0 = tables[0].find_all('tr')[1:]
        for row_t0 in rows_t0:
            if "Fuzzer count" in row_t0.text:
                fuzzer_count = row_t0.find_all('td')[1].text.strip()
                print(f"\tFUZZERS: {fuzzer_count}")
                break        

        div_container = project_profile_wrapper.find('div', class_='container') # <div class="project__profile-fuzzers">
        if div_container is None:
            print(f"Failed to find div container for {target}")
            # print(f"Failed to find div container for {target}")
            # no statistics, just produce a list of 20 fuzzers scraping elsewhere
            continue
        # get its first div
        div = div_container.find('div')
        # get its first table
        table = div.find('table')
        rows_t1 = table.find_all('tr')[1:]
        tmp = {} # and then sort them by coverage

        for row_t1 in rows_t1:
            # get the first td
            type = row_t1.find_all('td')[0]
            type = type.text.replace('(plot)', '').strip()
            coverage = row_t1.find_all('td')[1]
            import re  
            # parse this 4.09% (avg: 4.1%, max: 4.11%) -> get only avg
            coverage = re.search(r'avg: ([0-9.]+)%', coverage.text).group(1)
            tmp[type] = coverage
        # sort and print top N
        sorted_tmp = sorted(tmp.items(), key=lambda x: float(x[1]), reverse=True)
        print("\tTOP N*2 BY AVG COVERAGE:")
        for i, (type, coverage) in enumerate(sorted_tmp[:N*2]):
            print(f"\t\t{i+1}. {type}: {coverage}%")
            count += 1
        # now write the harnesses NAMES one per line inside the file ./fuzzing/$PROJECT_NAME/HARNESSES.txt
        # mkdir fuzzing/$PROJECT_NAME if it doesn't exist
        os.makedirs(f"./fuzzing/{target}", exist_ok=True)
        with open(f"./fuzzing/{target}/HARNESSES.txt", "w") as f:
            for i, (type, coverage) in enumerate(sorted_tmp[:N]):
                f.write(type + "\n")
            

    else:
        print(f"Failed to retrieve data for {target}, status code: {response.status_code}")
print("TOTAL FUZZERS TO SCHEDULE " + str(count))