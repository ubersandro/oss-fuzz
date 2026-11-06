from playwright.sync_api import sync_playwright
import re
import sys
import pandas as pd
import os
import pyaml
MAX_PRJ=os.environ.get("MAX_PRJ", 60) # default to 60 if not set

def scrape_oss_fuzz_ids(N=4000):
    url = "https://issues.oss-fuzz.com/issues?q=type:(vulnerability)"
    to_extract = N
    extracted = 0
    with open("database.csv", "w") as f:
        f.write("project,created,id\n")

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False, args=["--start-maximized"], timeout = 60000)
        page = browser.new_page()
        issue_ids = [] # array of dicts with ID, time
        page.goto(url)
        try:
            page.wait_for_selector('a.row-issue-id', timeout=15000)
        except Exception:
            print("Failed to find the issue IDs in time.")
            browser.close()
            return  
        
        #remove column LAST MODIFIED
        page.click('div[aria-label="Last modified column configuration"]', timeout=5000)
        remove_column = page.get_by_text(re.compile("remove column", re.IGNORECASE))
        remove_column.wait_for(state="visible", timeout=1000)
        remove_column.click()
        page.wait_for_timeout(1000) 

        # add column CREATED by clicking on the button with aria-label "Id column configuration"
        page.click('div[aria-label="Id column configuration"]', timeout=5000)
        add_column_right = page.get_by_text(re.compile("add column right", re.IGNORECASE))
        add_column_right.wait_for(state="visible", timeout=5000)
        add_column_right.click()
        created_option = page.get_by_text("Created", exact=True)        
        created_option.wait_for(state="visible", timeout=1000)            
        created_option.click()        
        # SORT 
        page.click('div[aria-label="CREATED, sortable"]', timeout=5000)            
        
        while True:
            try:
                page.wait_for_selector('a.row-issue-id', timeout=15000, state="visible")
                page.wait_for_selector('td.datetime-cell', timeout=15000, state="visible")
                page.wait_for_selector('a.row-issue-title', timeout=15000, state="visible")
            except Exception:
                print("Failed to find the issue IDs in time.")
                browser.close()
                return
            
            # ID
            page.wait_for_selector('a.row-issue-id', timeout=5000, state="visible")
            raw_ids = page.locator('a.row-issue-id').all_inner_texts()
            id_len = len(raw_ids)
            
            # CREATION TIME
            page.wait_for_timeout(1000) # wait for 1 second to ensure the page is fully loaded
            page.wait_for_selector('td.datetime-cell', timeout=5000, state="visible")
            created_times = page.locator('td.datetime-cell').all_inner_texts() # WORKING
            created_len = len(created_times)

            # PROJECT NAME
            page.wait_for_selector('a.row-issue-title', timeout=5000, state="visible")
            titles = page.locator('a.row-issue-title').all_inner_texts()
            title_len = len(titles)
            for t in titles:
                first_word = t.split(":")[0]
                titles[titles.index(t)] = first_word.strip()
            assert(id_len == created_len), f"Length mismatch: {id_len} IDs vs {created_len} created times"
            assert(id_len == title_len), f"Length mismatch: {id_len} IDs vs {title_len} titles"

            # create CSV entry
            issue_ids = [{"project": title.strip(), "created": created.strip(), "id": text.strip()} for text, created, title in zip(raw_ids, created_times, titles) if text.strip() and created.strip() and title.strip()]
            extracted += len(issue_ids)
            with open("database.csv", "a") as f:
                for issue in issue_ids:
                    created_time = issue['created'].replace("," , "")
                    f.write(f"{issue['project']},{created_time},{issue['id']}\n")

            page.click('button[aria-label="Go to next page"]', timeout=5000)
            print(extracted, " extracted so far")
            if(extracted >= to_extract):
                break
            
        
        browser.close()
        return issue_ids

def compute_statistics(df):
    # sort DF by created time
    df['created'] = pd.to_datetime(df['created'], format='%b %d %Y %I:%M%p') # SPECIFY FORMAT -> Feb 17 2024 08:30AM,42533052
    df = df.sort_values(by='created')
    min_time = df['created'].min()
    max_time = df['created'].max()
    print(f"MIN TIME: {min_time}")
    print(f"MAX TIME: {max_time}")
    # rank projects based on how many times they appear in the database
    project_counts = df['project'].value_counts()
    print("PROJECT RANKING:")
    i = MAX_PRJ
    with open("projects.txt", "w") as ff:
        for project, count in project_counts.items():
            if i <= 0:
                break
                print("____________________________________________")

            project_yaml_path = f"/home/ubuntu/ubersandro/oss-fuzz/projects/{project}/project.yaml"
            if os.path.exists(project_yaml_path):
                with open(project_yaml_path, "r") as f:
                    content = f.read()
                    yaml_data = pyaml.yaml.safe_load(content)
                    LANG_MD = yaml_data.get('language', None)
                    MAIN_REPO = yaml_data.get('main_repo', None)
                    LANG_FROM_GH = None
                    # ENDPOINT https://api.github.com/repos/USER/PROJECT/languages
                    if MAIN_REPO:
                        # extract user and project from MAIN_REPO
                        match = re.search(r"github\.com/([^/]+)/([^/]+)", MAIN_REPO)
                        if match:
                            user, repo = match.groups()
                            user = user.lower()
                            repo = repo.lower()
                            # make a request to the GitHub API to get the languages
                            import requests
                            api_url = f"https://api.github.com/repos/{user}/{repo}/languages"
                            response = requests.get(api_url)
                            if response.status_code == 200:
                                LANG_FROM_GH = list(response.json().keys())
                                print(f"LANGUAGES FROM GITHUB API: {LANG_FROM_GH}")
                            else:
                                print(f"Failed to fetch languages from GitHub API for {MAIN_REPO}. Status code: {response.status_code}")
                    # example PROJECT: libraw, COUNT: 23, LANGUAGE (from YAML): c++, LANGUAGE (from GitHub API): ['C++', 'C', 'M4', 'QMake', 'Makefile', 'Shell', 'Perl']                                                                                                                                                                  
                    if LANG_FROM_GH:
                        LANG_FROM_GH = LANG_FROM_GH[0].lower() # take the first language and convert to lowercase
                    print(f"PROJECT:{project}, COUNT:{count}, LANGUAGE (from YAML):{LANG_MD}, LANGUAGE (from GitHub API):{LANG_FROM_GH}")
                    ff.write(f"{project}:{count}:{LANG_FROM_GH if LANG_FROM_GH else LANG_MD}\n")
                    i -= 1
            #         if "language: " in content:
            #             language = content.split("language: ")[1].split("\n")[0].strip()
            #             if 'c' in language.lower():
            #                 print(f"{project}:{count}:{language}")
            #                 ff.write(f"{project}:{count}:{language}\n")
            #                 i = i - 1
            # use GH apis instead 
            # curl -s https://api.github.com/repos/ffmpeg/ffmpeg/languages
            # using main repo from the project yaml

if __name__ == "__main__":
    val = os.environ.get("SCRAPE", "0") # default to 0 if not set

    if val and val == "1":
        if len(sys.argv) > 1:
            n = int(sys.argv[1])
            scrape_oss_fuzz_ids(n)
        else:
            scrape_oss_fuzz_ids()

    df = pd.read_csv("./database.csv")
    # print number of vulns and first 10 rows
    print(f"NUMBER OF VULNERABILITIES: {len(df)}")
    print("FIRST 10 VULNERABILITIES:")
    print(df.head(10))
    N = len(df)
    compute_statistics(df)
