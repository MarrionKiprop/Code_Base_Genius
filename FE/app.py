import streamlit as st
import requests
import os

st.set_page_config(page_title="CodeGenius", page_icon="🤖", layout="wide")

st.title("CodeGenius — Auto Repo Documenter")
st.write("Enter a GitHub repository link to generate AI-powered documentation.")

repo_url = st.text_input("🔗 GitHub Repo URL", placeholder="https://github.com/jaseci/jaseci.git")

API_URL = "http://localhost:8000/walker/codegenius_supervisor"

if st.button("Generate Documentation"):
    if not repo_url.strip():
        st.error("Please enter a valid GitHub URL.")
    else:
        st.info("Processing... this may take a few seconds ⏳")
        try:
            res = requests.post(API_URL, json={"repo_url": repo_url}, timeout=900)
            data = res.json()

            if "error" in data:
                st.error(data["error"])
            else:
                reports = data.get("reports", [])
                if not reports:
                    st.warning("No report returned by the backend.")
                else:
                    report = reports[0]
                    st.success(f"Repo processed successfully! Parsed {report.get('files_parsed', 0)} files.")
                    summary_path = report.get("output_md", "")
                    st.write(f"Markdown generated: `{summary_path}`")

                    # Display Markdown content inline
                    markdown_text = report.get("markdown_text", "")
                    if markdown_text:
                        st.divider()
                        st.markdown("### Generated Documentation")
                        st.markdown(
                            f"<div style='max-height:600px; overflow:auto; padding:10px; border-radius:8px; background-color:#0e1117'>{markdown_text}</div>",
                            unsafe_allow_html=True
                        )
                    else:
                        st.info("No markdown content received.")
        except Exception as e:
            st.error(f"Error: {e}")
