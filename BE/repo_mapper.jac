#agents/repo_mapper.jac
import from byllm.llm { Model }
import from git { Repo }
import os;
import re;
import tempfile;
import shutil;
import from repo_utils { clone_repo, collect_files, write_tree }

glob llm = Model(model_name="openai/gpt-4o-mini", verbose=False);

node RepoMapper {
    has repo_url: str;
    has temp_dir: str = "";
    has repo_path: str = "";
    has readme_summary: str = "";
    has file_index: list[str] = [];
    has file_tree_txt: str = "";

    def summarize_readme(text: str) -> str by llm(method="ReAct");

    can map with entry {
        (self.temp_dir, self.repo_path) = clone_repo(self.repo_url);

        readme = os.path.join(self.repo_path, "README.md");
        if os.path.exists(readme) {
            content = open(readme, "r", encoding="utf-8").read();
            self.readme_summary = self.summarize_readme(content);
        } else {
            self.readme_summary = "No README found.";
        }

        self.file_index = collect_files(self.repo_path);
        self.file_tree_txt = write_tree(self.repo_path, self.file_index);
        print("Indexed " + str(len(self.file_index)) + " files.");
    }
}

sem RepoMapper.summarize_readme = """
Summarize README into concise bullets:
- Purpose
- Features
- Installation
- Usage
- Entry points
Limit to ~10 bullets.
""";